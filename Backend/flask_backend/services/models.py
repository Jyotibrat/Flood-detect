"""
Model Service Module
Handles loading and running flood prediction models (XGBoost and RL).
"""

import json
import logging
import os
from typing import Dict, List, Optional

import numpy as np

logger = logging.getLogger(__name__)

# Model file paths (relative to project root)
MODELS_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "models",
)
XGBOOST_MODEL_PATH = os.path.join(MODELS_DIR, "xgboost_flood_model.json")
RL_MODEL_PATH = os.path.join(MODELS_DIR, "rl_flood_model.pth")


class ModelService:
    """
    Service for loading and running flood prediction models.

    Supports:
    - XGBoost model (.json / .model format)
    - Reinforcement Learning model (PyTorch serialized)

    If models are not available, uses statistical heuristic fallback
    to still provide predictions based on weather data patterns.
    """

    # Feature names expected by models
    FEATURE_NAMES = [
        "avg_temperature",
        "max_temperature",
        "min_temperature",
        "total_precipitation",
        "avg_precipitation",
        "max_daily_precipitation",
        "avg_humidity",
        "max_wind_speed",
        "avg_soil_moisture",
        "precipitation_trend",  # slope of precip over days
        "temp_range",
        "consecutive_rain_days",
    ]

    def __init__(self):
        self.xgboost_model = None
        self.rl_model = None
        self.xgboost_loaded = False
        self.rl_loaded = False

        self._load_models()

    def _load_models(self):
        """Attempt to load both models from disk."""
        self._load_xgboost()
        self._load_rl()

    def _load_xgboost(self):
        """Load XGBoost model from file."""
        if not os.path.exists(XGBOOST_MODEL_PATH):
            logger.warning(
                f"XGBoost model not found at {XGBOOST_MODEL_PATH}. "
                "Using heuristic fallback."
            )
            return

        try:
            import xgboost as xgb

            self.xgboost_model = xgb.Booster()
            self.xgboost_model.load_model(XGBOOST_MODEL_PATH)
            self.xgboost_loaded = True
            logger.info("XGBoost model loaded successfully")
        except ImportError:
            logger.warning(
                "xgboost package not installed. "
                "Using heuristic fallback."
            )
        except Exception as e:
            logger.error(f"Failed to load XGBoost model: {e}")

    def _load_rl(self):
        """Load RL model from file."""
        if not os.path.exists(RL_MODEL_PATH):
            logger.warning(
                f"RL model not found at {RL_MODEL_PATH}. "
                "Using heuristic fallback."
            )
            return

        try:
            import torch

            self.rl_model = torch.load(
                RL_MODEL_PATH, map_location="cpu"
            )
            self.rl_model.eval()
            self.rl_loaded = True
            logger.info("RL model loaded successfully")
        except ImportError:
            logger.warning(
                "PyTorch not installed. Using heuristic fallback."
            )
        except Exception as e:
            logger.error(f"Failed to load RL model: {e}")

    def preprocess_weather_data(
        self, weather_data: List[Dict]
    ) -> Optional[np.ndarray]:
        """
        Transform raw weather data into model-ready feature vector.

        Args:
            weather_data: List of daily weather records.

        Returns:
            Numpy array of shape (1, n_features) or None on failure.
        """
        if not weather_data:
            logger.error("No weather data to preprocess")
            return None

        try:
            temps_max = []
            temps_min = []
            temps_mean = []
            precipitations = []
            humidities = []
            wind_speeds = []
            soil_moistures = []

            for day in weather_data:
                temp = day.get("temperature", {})
                precip = day.get("precipitation", {})
                humid = day.get("humidity", {})
                wind = day.get("wind_speed", {})
                soil = day.get("soil_moisture", {})

                temps_max.append(temp.get("max") or 0.0)
                temps_min.append(temp.get("min") or 0.0)
                temps_mean.append(temp.get("mean") or 0.0)
                precipitations.append(precip.get("total") or 0.0)
                humidities.append(humid.get("mean") or 0.0)
                wind_speeds.append(wind.get("max") or 0.0)
                soil_moistures.append(soil.get("mean") or 0.0)

            # Compute aggregate features
            avg_temp = np.mean(temps_mean) if temps_mean else 0.0
            max_temp = np.max(temps_max) if temps_max else 0.0
            min_temp = np.min(temps_min) if temps_min else 0.0
            total_precip = np.sum(precipitations)
            avg_precip = np.mean(precipitations)
            max_daily_precip = np.max(precipitations)
            avg_humidity = np.mean(humidities) if humidities else 0.0
            max_wind = np.max(wind_speeds) if wind_speeds else 0.0
            avg_soil = np.mean(soil_moistures) if soil_moistures else 0.0

            # Precipitation trend (simple linear slope)
            if len(precipitations) > 1:
                x = np.arange(len(precipitations))
                precip_trend = float(np.polyfit(x, precipitations, 1)[0])
            else:
                precip_trend = 0.0

            temp_range = max_temp - min_temp

            # Consecutive rain days
            consecutive_rain = 0
            max_consecutive = 0
            for p in precipitations:
                if p > 0.1:  # > 0.1mm counts as rain
                    consecutive_rain += 1
                    max_consecutive = max(max_consecutive, consecutive_rain)
                else:
                    consecutive_rain = 0

            features = np.array([[
                avg_temp,
                max_temp,
                min_temp,
                total_precip,
                avg_precip,
                max_daily_precip,
                avg_humidity,
                max_wind,
                avg_soil,
                precip_trend,
                temp_range,
                float(max_consecutive),
            ]])

            logger.info(
                f"Preprocessed features: shape={features.shape}, "
                f"total_precip={total_precip:.1f}mm, "
                f"avg_humidity={avg_humidity:.1f}%"
            )

            return features

        except Exception as e:
            logger.error(f"Feature preprocessing error: {e}")
            return None

    def predict_xgboost(
        self, features: np.ndarray
    ) -> Dict:
        """
        Run prediction using XGBoost model.

        If the model is not loaded, falls back to a statistical
        heuristic based on the feature values.

        Args:
            features: Feature array of shape (1, n_features).

        Returns:
            Dict with prediction, probability, and confidence.
        """
        if self.xgboost_loaded and self.xgboost_model is not None:
            try:
                import xgboost as xgb

                dmatrix = xgb.DMatrix(
                    features, feature_names=self.FEATURE_NAMES
                )
                probability = float(
                    self.xgboost_model.predict(dmatrix)[0]
                )
                prediction = "Flood" if probability >= 0.5 else "No Flood"
                confidence = abs(probability - 0.5) * 2  # 0-1 scale

                return {
                    "prediction": prediction,
                    "probability": round(probability, 4),
                    "confidence": round(confidence, 4),
                }
            except Exception as e:
                logger.error(f"XGBoost model inference error: {e}")

        # Heuristic fallback
        return self._heuristic_prediction(features, model_name="xgboost")

    def predict_rl(self, features: np.ndarray) -> Dict:
        """
        Run prediction using RL model.

        If the model is not loaded, falls back to a statistical
        heuristic (with slightly different weighting than XGBoost).

        Args:
            features: Feature array of shape (1, n_features).

        Returns:
            Dict with prediction, probability, and confidence.
        """
        if self.rl_loaded and self.rl_model is not None:
            try:
                import torch

                tensor = torch.FloatTensor(features)
                with torch.no_grad():
                    output = self.rl_model(tensor)
                    if hasattr(output, "item"):
                        probability = float(
                            torch.sigmoid(output).item()
                        )
                    else:
                        probability = float(
                            torch.sigmoid(output[0]).item()
                        )

                prediction = "Flood" if probability >= 0.5 else "No Flood"
                confidence = abs(probability - 0.5) * 2

                return {
                    "prediction": prediction,
                    "probability": round(probability, 4),
                    "confidence": round(confidence, 4),
                }
            except Exception as e:
                logger.error(f"RL model inference error: {e}")

        # Heuristic fallback with RL-style weighting
        return self._heuristic_prediction(features, model_name="rl")

    def _heuristic_prediction(
        self, features: np.ndarray, model_name: str = "heuristic"
    ) -> Dict:
        """
        Statistical heuristic fallback when ML models are unavailable.

        Uses weighted scoring based on known flood risk factors:
        - Heavy precipitation (most important)
        - High humidity
        - High soil moisture (saturation)
        - Consecutive rain days
        - Precipitation trend

        Args:
            features: Feature array.
            model_name: Name tag for the source.

        Returns:
            Dict with prediction, probability, and confidence.
        """
        try:
            f = features[0]

            # Extract key features
            total_precip = f[3]      # total_precipitation
            avg_precip = f[4]        # avg_precipitation
            max_daily_precip = f[5]  # max_daily_precipitation
            avg_humidity = f[6]      # avg_humidity
            avg_soil_moisture = f[8] # avg_soil_moisture
            precip_trend = f[9]      # precipitation_trend
            consecutive_rain = f[11] # consecutive_rain_days

            # Scoring system (0-1 scale per factor)
            scores = []

            # Precipitation score (0-1)
            # Heavy rain: >50mm total is significant, >100mm critical
            precip_score = min(total_precip / 100.0, 1.0)
            scores.append(("precipitation", precip_score, 0.30))

            # Max daily precipitation score
            # >30mm/day is heavy, >50mm very heavy
            max_precip_score = min(max_daily_precip / 50.0, 1.0)
            scores.append(("max_daily_precip", max_precip_score, 0.20))

            # Humidity score
            # >80% is high humidity
            humidity_score = max(0, (avg_humidity - 50) / 50.0)
            humidity_score = min(humidity_score, 1.0)
            scores.append(("humidity", humidity_score, 0.15))

            # Soil moisture score
            # >0.3 m³/m³ is high
            soil_score = min(avg_soil_moisture / 0.4, 1.0)
            scores.append(("soil_moisture", soil_score, 0.10))

            # Consecutive rain days score
            # >5 days is concerning
            rain_days_score = min(consecutive_rain / 7.0, 1.0)
            scores.append(("consecutive_rain", rain_days_score, 0.15))

            # Precipitation trend score (positive = increasing)
            trend_score = max(0, min(precip_trend / 5.0, 1.0))
            scores.append(("precip_trend", trend_score, 0.10))

            # Weighted sum
            probability = sum(
                score * weight for _, score, weight in scores
            )
            probability = max(0.0, min(1.0, probability))

            # Add slight variation between xgboost and rl heuristics
            if model_name == "rl":
                # RL tends to be slightly more conservative
                probability = probability * 0.95 + 0.025

            prediction = "Flood" if probability >= 0.5 else "No Flood"

            # Confidence is lower for heuristic predictions
            base_confidence = abs(probability - 0.5) * 2
            confidence = base_confidence * 0.7  # 30% penalty for heuristic

            logger.info(
                f"Heuristic ({model_name}) prediction: "
                f"prob={probability:.4f}, "
                f"conf={confidence:.4f}, "
                f"factors={[(n, f'{s:.2f}') for n, s, _ in scores]}"
            )

            return {
                "prediction": prediction,
                "probability": round(probability, 4),
                "confidence": round(confidence, 4),
            }

        except Exception as e:
            logger.error(f"Heuristic prediction failed: {e}")
            return {
                "prediction": "Unknown",
                "probability": 0.5,
                "confidence": 0.0,
            }
