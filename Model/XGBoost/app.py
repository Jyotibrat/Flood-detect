from xgboost import XGBRegressor
import numpy as np

# Load model
model = XGBRegressor()
model.load_model("flood_model.json")

def predict(data):
    data = np.array(data)
    prediction = model.predict(data)
    return prediction.tolist()