
import joblib
import numpy as np

# Load model
model = joblib.load("flood_model.joblib")

# Same threshold used in training
THRESHOLD = 0.40

def predict(data):
    '''
    data: list or numpy array of shape (n_samples, n_features)
    '''
    data = np.array(data)
    
    probs = model.predict_proba(data)[:, 1]
    preds = (probs > THRESHOLD).astype(int)
    
    return {
        "probabilities": probs.tolist(),
        "predictions": preds.tolist()
    }
