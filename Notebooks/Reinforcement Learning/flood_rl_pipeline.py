"""
=============================================================================
INDOFLOODS — Reinforcement Learning Flood Prediction Pipeline
=============================================================================
TARGET  : Predict whether a flood event will be a "Flood" or "Severe Flood"
          using the 10-day cumulative precipitation before the event start date,
          enriched with static catchment characteristics.

RL APPROACH
-----------
We frame flood prediction as a sequential decision-making problem:
  • The "Agent" is a policy network that reads weather + catchment features.
  • The "Environment" is a custom Gym environment built from the dataset.
  • Each "step" presents one flood event; the agent predicts flood severity.
  • The agent receives a reward based on prediction correctness.
  • We train with PPO (Proximal Policy Optimization) via Stable-Baselines3.

Algorithm : PPO (on-policy, works well for discrete action spaces)
Why PPO?  : Stable, sample-efficient, handles tabular-style observations well.

Files required (place in same directory):
  - catchment_characteristics_indofloods.csv
  - floodevents_indofloods.csv
  - precipitation_variables_indofloods.csv
  - metadata_indofloods.csv

INSTALL (run once):
  pip install stable-baselines3 gymnasium pandas scikit-learn numpy matplotlib
=============================================================================
"""

# ── Imports ──────────────────────────────────────────────────────────────────
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix, ConfusionMatrixDisplay

import gymnasium as gym
from gymnasium import spaces
from stable_baselines3 import PPO
from stable_baselines3.common.env_checker import check_env
from stable_baselines3.common.callbacks import EvalCallback
from stable_baselines3.common.monitor import Monitor


# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

# ── Paths: script and CSVs must be in the same folder ────────────────────────
DATA_DIR = os.path.dirname(os.path.abspath(__file__))

CATCHMENT_FILE  = os.path.join(DATA_DIR, "catchment_characteristics_indofloods.csv")
FLOOD_FILE      = os.path.join(DATA_DIR, "floodevents_indofloods.csv")
PRECIP_FILE     = os.path.join(DATA_DIR, "precipitation_variables_indofloods.csv")
META_FILE       = os.path.join(DATA_DIR, "metadata_indofloods.csv")

# ── Hyperparameters ───────────────────────────────────────────────────────────
REWARD_CORRECT         = +1.0
REWARD_WRONG           = -1.5
REWARD_CORRECT_SEVERE  = +3.0
REWARD_MISS_SEVERE     = -4.0

TOTAL_TIMESTEPS = 1_000_000
EVAL_FREQ       = 5_000
N_EVAL_EPISODES = 50
LEARNING_RATE   = 1e-4
N_STEPS         = 2048
BATCH_SIZE      = 64
N_EPOCHS        = 10

SEED = 42

ACTION_FLOOD        = 0
ACTION_SEVERE_FLOOD = 1


# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — DATA LOADING & PREPROCESSING
# ══════════════════════════════════════════════════════════════════════════════

def load_and_merge_data():
    print("\n[1/4] Loading data files...")
    floods = pd.read_csv(FLOOD_FILE)
    precip = pd.read_csv(PRECIP_FILE)
    catch  = pd.read_csv(CATCHMENT_FILE)
    meta   = pd.read_csv(META_FILE)

    print(f"      Flood events   : {floods.shape[0]} rows")
    print(f"      Precipitation  : {precip.shape[0]} rows")
    print(f"      Catchments     : {catch.shape[0]} rows")
    print(f"      Metadata       : {meta.shape[0]} rows")

    # ── Extract GaugeID from EventID ─────────────────────────────────────────
    # EventID format: INDOFLOODS-gauge-118-10  →  GaugeID: INDOFLOODS-gauge-118
    def event_to_gauge(event_id):
        parts = str(event_id).rsplit("-", 1)
        return parts[0]

    floods["GaugeID"] = floods["EventID"].apply(event_to_gauge)
    precip["GaugeID"] = precip["EventID"].apply(event_to_gauge)

    # ── Merge precipitation + flood events on EventID ─────────────────────────
    print("\n[2/4] Merging precipitation with flood events...")
    precip_cols = ["EventID", "T1d", "T2d", "T3d", "T4d", "T5d",
                   "T6d", "T7d", "T8d", "T9d", "T10d"]
    df = floods.merge(precip[precip_cols], on="EventID", how="inner")
    print(f"      After merge    : {df.shape[0]} rows")

    # ── Merge with catchment characteristics on GaugeID ──────────────────────
    print("\n[3/4] Merging with catchment characteristics...")

    # Build catchment numeric table with GaugeID
    catch_numeric = catch.select_dtypes(include=[np.number]).copy()
    catch_numeric["GaugeID"] = catch["GaugeID"].values

    # Ensure GaugeID exists in df (it should from floods merge above)
    if "GaugeID" not in df.columns:
        df["GaugeID"] = df["EventID"].apply(event_to_gauge)

    df = df.merge(catch_numeric, on="GaugeID", how="left", suffixes=("", "_catch"))
    print(f"      After catch merge: {df.shape[0]} rows")

    # ── Build label: 0 = Flood, 1 = Severe Flood ─────────────────────────────
    print("\n[4/4] Building labels & feature matrix...")
    df["label"] = (df["Flood Type"] == "Severe Flood").astype(int)

    # ── Drop all non-feature columns ──────────────────────────────────────────
    drop_cols = {
        "EventID", "GaugeID", "Start Date", "End Date",
        "Peak Flood Level (m)", "Peak FL Date", "Num Peak FL",
        "Peak Discharge Q (cumec)", "Peak Discharge Date",
        "Flood Volume (cumec)", "Event Duration (days)",
        "Time to Peak (days)", "Recession Time (day)",
        "Flood Type", "label"
    }

    feature_cols = [
        c for c in df.columns
        if c not in drop_cols
        and pd.api.types.is_numeric_dtype(df[c])
    ]

    print(f"      Total features   : {len(feature_cols)}")
    print(f"      Precipitation    : {len([c for c in feature_cols if c.startswith('T')])}")
    print(f"      Catchment        : {len([c for c in feature_cols if not c.startswith('T')])}")

    X = df[feature_cols].copy()
    y = df["label"].copy()

    # Fill missing values with column median
    X = X.fillna(X.median())

    print(f"\n      Class distribution:")
    print(f"        Flood        : {(y==0).sum()} ({(y==0).mean()*100:.1f}%)")
    print(f"        Severe Flood : {(y==1).sum()} ({(y==1).mean()*100:.1f}%)")

    return X.values, y.values, feature_cols


# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — CUSTOM GYM ENVIRONMENT
# ══════════════════════════════════════════════════════════════════════════════

class FloodPredictionEnv(gym.Env):
    """
    Custom Gymnasium environment for flood severity prediction.

    Observation : scaled feature vector for one flood event
    Action      : 0 = Flood, 1 = Severe Flood
    Reward      : asymmetric — higher reward/penalty for severe floods
    Episode     : one full pass through the dataset
    """

    metadata = {"render_modes": []}

    def __init__(self, X: np.ndarray, y: np.ndarray, mode: str = "train"):
        super().__init__()
        self.X = X.astype(np.float32)
        self.y = y.astype(np.int32)
        self.mode = mode
        self.n_samples = len(X)
        self.current_idx = 0
        self.correct_preds = 0
        self.total_preds   = 0

        n_features = X.shape[1]
        self.observation_space = spaces.Box(
            low=-np.inf, high=np.inf, shape=(n_features,), dtype=np.float32
        )
        self.action_space = spaces.Discrete(2)

    def _get_obs(self):
        return self.X[self.current_idx]

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)
        self.current_idx = 0
        self.correct_preds = 0
        self.total_preds   = 0
        # Replace any NaN/inf with 0
        self.X = np.nan_to_num(self.X, nan=0.0, posinf=0.0, neginf=0.0)
        return self._get_obs(), {}

    def step(self, action):
        true_label = self.y[self.current_idx]

        if action == true_label:
            reward = REWARD_CORRECT_SEVERE if true_label == ACTION_SEVERE_FLOOD else REWARD_CORRECT
            self.correct_preds += 1
        else:
            if true_label == ACTION_SEVERE_FLOOD and action == ACTION_FLOOD:
                reward = REWARD_MISS_SEVERE
            else:
                reward = REWARD_WRONG

        self.total_preds  += 1
        self.current_idx  += 1

        terminated = (self.current_idx >= self.n_samples)
        truncated  = False

        obs  = self._get_obs() if not terminated else np.zeros(self.X.shape[1], dtype=np.float32)
        info = {"accuracy": self.correct_preds / self.total_preds if self.total_preds > 0 else 0.0}

        return obs, reward, terminated, truncated, info

    def render(self):
        pass


# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 — TRAINING
# ══════════════════════════════════════════════════════════════════════════════

def train_rl_agent(X_train, y_train, X_val, y_val):
    print("\n" + "="*60)
    print("TRAINING PPO AGENT")
    print("="*60)

    train_env = FloodPredictionEnv(X_train, y_train, mode="train")
    val_env   = Monitor(FloodPredictionEnv(X_val, y_val, mode="val"))

    print("\nValidating environment API...")
    check_env(train_env, warn=True)
    print("Environment OK ✓")

    eval_callback = EvalCallback(
        val_env,
        best_model_save_path="./best_model/",
        log_path="./logs/",
        eval_freq=EVAL_FREQ,
        n_eval_episodes=N_EVAL_EPISODES,
        deterministic=True,
        verbose=1
    )

    model = PPO(
        policy="MlpPolicy",
        env=train_env,
        learning_rate=LEARNING_RATE,
        n_steps=N_STEPS,
        batch_size=BATCH_SIZE,
        n_epochs=N_EPOCHS,
        gamma=0.99,
        gae_lambda=0.95,
        clip_range=0.2,
        ent_coef=0.01,
        verbose=1,
        seed=SEED,
        policy_kwargs=dict(net_arch=[256, 256])
    )

    print(f"\nStarting training for {TOTAL_TIMESTEPS:,} timesteps...")
    model.learn(
        total_timesteps=TOTAL_TIMESTEPS,
        callback=eval_callback,
        progress_bar=True
    )

    print("\nTraining complete ✓")
    return model


# ══════════════════════════════════════════════════════════════════════════════
# STEP 5 — EVALUATION
# ══════════════════════════════════════════════════════════════════════════════

def evaluate_agent(model, X_test, y_test):
    print("\n" + "="*60)
    print("EVALUATION ON TEST SET")
    print("="*60)

    predictions = []
    test_env = FloodPredictionEnv(X_test, y_test, mode="test")
    obs, _ = test_env.reset()

    for i in range(len(y_test)):
        action, _ = model.predict(obs, deterministic=True)
        predictions.append(int(action))
        obs, _, terminated, truncated, _ = test_env.step(action)
        if terminated or truncated:
            break

    true_labels = y_test[:len(predictions)].tolist()

    print("\nClassification Report:")
    print(classification_report(
        true_labels, predictions,
        target_names=["Flood", "Severe Flood"]
    ))

    cm = confusion_matrix(true_labels, predictions)
    print("Confusion Matrix:")
    print(cm)

    # ── Plot ──────────────────────────────────────────────────────────────────
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    disp = ConfusionMatrixDisplay(confusion_matrix=cm, display_labels=["Flood", "Severe Flood"])
    disp.plot(ax=axes[0], colorbar=False, cmap="Blues")
    axes[0].set_title("Confusion Matrix — RL Agent (PPO)")

    pred_arr = np.array(predictions)
    true_arr = np.array(true_labels)
    axes[1].bar(
        ["Flood\n(True)", "Severe\n(True)", "Flood\n(Pred)", "Severe\n(Pred)"],
        [(true_arr==0).sum(), (true_arr==1).sum(), (pred_arr==0).sum(), (pred_arr==1).sum()],
        color=["steelblue", "tomato", "lightblue", "lightsalmon"],
        edgecolor="black"
    )
    axes[1].set_title("Prediction vs Ground Truth Distribution")
    axes[1].set_ylabel("Count")

    plt.tight_layout()
    plot_path = os.path.join(DATA_DIR, "flood_rl_results.png")
    plt.savefig(plot_path, dpi=150)
    print(f"\nPlot saved to: {plot_path}")

    return predictions, true_labels


# ══════════════════════════════════════════════════════════════════════════════
# STEP 6 — PREDICT ON NEW DATA
# ══════════════════════════════════════════════════════════════════════════════

def predict_new_event(model, scaler, feature_cols, precipitation_10days, catchment_features=None):
    """
    Predict flood severity for a new event.

    Args:
        precipitation_10days : list of 10 cumulative precip values [T1d..T10d] in mm
        catchment_features   : dict of catchment values (optional)

    Returns:
        str : "Flood" or "Severe Flood"

    Example:
        precip = [32.8, 65.2, 99.4, 124.2, 133.3, 138.1, 140.4, 155.2, 177.3, 203.6]
        result = predict_new_event(model, scaler, feature_cols, precip)
        print(result)
    """
    row = {}
    for i, name in enumerate([f"T{i}d" for i in range(1, 11)]):
        row[name] = precipitation_10days[i] if i < len(precipitation_10days) else 0.0

    if catchment_features:
        row.update(catchment_features)

    feat_vec = np.array([row.get(col, 0.0) for col in feature_cols], dtype=np.float32)
    feat_vec = scaler.transform(feat_vec.reshape(1, -1)).astype(np.float32)

    action, _ = model.predict(feat_vec[0], deterministic=True)
    return {ACTION_FLOOD: "Flood", ACTION_SEVERE_FLOOD: "Severe Flood"}[int(action)]


# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

def main():
    print("=" * 60)
    print("INDOFLOODS — RL Flood Prediction (PPO)")
    print("=" * 60)

    # Load & merge all files
    X, y, feature_cols = load_and_merge_data()

    # Scale features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X).astype(np.float32)

    # Split: 70% train / 15% val / 15% test
    X_train, X_temp, y_train, y_temp = train_test_split(
        X_scaled, y, test_size=0.30, random_state=SEED, stratify=y
    )
    X_val, X_test, y_val, y_test = train_test_split(
        X_temp, y_temp, test_size=0.50, random_state=SEED, stratify=y_temp
    )

    print(f"\nData split:")
    print(f"  Train : {len(X_train)} samples")
    print(f"  Val   : {len(X_val)} samples")
    print(f"  Test  : {len(X_test)} samples")

    # Train
    model = train_rl_agent(X_train, y_train, X_val, y_val)

    # Evaluate
    evaluate_agent(model, X_test, y_test)

    # Save model
    model_path = os.path.join(DATA_DIR, "flood_rl_ppo_model")
    model.save(model_path)
    print(f"\nModel saved to: {model_path}.zip")

    # Example prediction with new data
    print("\n" + "=" * 60)
    print("EXAMPLE: Predicting a new event")
    print("=" * 60)
    example_precip = [46.3, 86.8, 104.8, 115.5, 125.9, 130.9, 134.2, 148.8, 167.9, 182.4]
    result = predict_new_event(model, scaler, feature_cols, example_precip)
    print(f"  Input (10-day cumulative precip mm): {example_precip}")
    print(f"  Predicted Flood Type               : {result}")

    print("\nDone! ✓")
    print("Files created:")
    print("  flood_rl_ppo_model.zip  — saved PPO model")
    print("  flood_rl_results.png    — evaluation plots")
    print("  best_model/             — best checkpoint during training")


if __name__ == "__main__":
    main()