"""
Flood Prediction Backend - Flask Application
Main entry point for the Flask-based flood prediction API.
"""

import os
import logging
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv

from services.weather import WeatherService
from services.models import ModelService
from services.gemini import GeminiService

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.FileHandler("flood_prediction.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)
CORS(app)

# Initialize services
weather_service = WeatherService()
model_service = ModelService()
gemini_service = GeminiService(api_key=os.getenv("GEMINI_API_KEY", ""))


@app.route("/", methods=["GET"])
def index():
    """Root endpoint — API info."""
    return jsonify({
        "name": "Flood Prediction API",
        "version": "1.0.0",
        "endpoints": {
            "POST /predict": "Get flood prediction for a location",
            "GET /health": "Health check",
        },
        "usage": "POST /predict with JSON body: "
                 '{"latitude": 28.61, "longitude": 77.20}',
    })


@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint."""
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "1.0.0",
        "services": {
            "weather": "operational",
            "models": {
                "xgboost": model_service.xgboost_loaded,
                "rl": model_service.rl_loaded,
            },
            "gemini": gemini_service.is_configured(),
        },
    })


@app.route("/predict", methods=["POST"])
def predict():
    """
    Main prediction endpoint.

    Accepts latitude/longitude, fetches weather data, runs models,
    and returns flood prediction with Gemini AI analysis.

    Request JSON:
        {
            "latitude": <float>,
            "longitude": <float>
        }

    If lat/lon not provided, falls back to IP-based geolocation.
    """
    request_id = datetime.utcnow().strftime("%Y%m%d%H%M%S%f")
    logger.info(f"[{request_id}] Received prediction request")

    try:
        # ──────────────────────────────────────────────
        # 1. Parse location from request
        # ──────────────────────────────────────────────
        data = request.get_json(silent=True) or {}
        latitude = data.get("latitude")
        longitude = data.get("longitude")

        if latitude is None or longitude is None:
            logger.info(f"[{request_id}] No coordinates provided, using IP geolocation")
            try:
                geo = weather_service.get_location_from_ip(
                    request.remote_addr
                )
                latitude = geo["latitude"]
                longitude = geo["longitude"]
                logger.info(
                    f"[{request_id}] IP geolocation resolved: "
                    f"({latitude}, {longitude})"
                )
            except Exception as e:
                logger.error(f"[{request_id}] IP geolocation failed: {e}")
                return jsonify({
                    "error": "Could not determine location. "
                             "Please provide latitude and longitude.",
                    "status": "error",
                }), 400
        else:
            try:
                latitude = float(latitude)
                longitude = float(longitude)
            except (ValueError, TypeError):
                return jsonify({
                    "error": "Invalid latitude or longitude values. "
                             "Must be numeric.",
                    "status": "error",
                }), 400

            if not (-90 <= latitude <= 90) or not (-180 <= longitude <= 180):
                return jsonify({
                    "error": "Latitude must be between -90 and 90, "
                             "longitude between -180 and 180.",
                    "status": "error",
                }), 400

        logger.info(
            f"[{request_id}] Processing prediction for "
            f"({latitude}, {longitude})"
        )

        # ──────────────────────────────────────────────
        # 2. Fetch historical weather data (last 10 days)
        # ──────────────────────────────────────────────
        try:
            weather_data = weather_service.fetch_historical_weather(
                latitude, longitude
            )
            logger.info(
                f"[{request_id}] Fetched {len(weather_data)} days of weather data"
            )
        except Exception as e:
            logger.error(f"[{request_id}] Weather data fetch failed: {e}")
            weather_data = []

        # ──────────────────────────────────────────────
        # 3. Run ML models
        # ──────────────────────────────────────────────
        xgboost_result = None
        rl_result = None
        models_failed = False

        try:
            processed_features = model_service.preprocess_weather_data(
                weather_data
            )
            logger.info(f"[{request_id}] Preprocessed features for model input")
        except Exception as e:
            logger.error(f"[{request_id}] Feature preprocessing failed: {e}")
            processed_features = None
            models_failed = True

        if processed_features is not None:
            # Run XGBoost model
            try:
                xgboost_result = model_service.predict_xgboost(
                    processed_features
                )
                logger.info(
                    f"[{request_id}] XGBoost prediction: "
                    f"{xgboost_result}"
                )
            except Exception as e:
                logger.error(
                    f"[{request_id}] XGBoost prediction failed: {e}"
                )

            # Run RL model
            try:
                rl_result = model_service.predict_rl(processed_features)
                logger.info(
                    f"[{request_id}] RL prediction: {rl_result}"
                )
            except Exception as e:
                logger.error(
                    f"[{request_id}] RL prediction failed: {e}"
                )

        if xgboost_result is None and rl_result is None:
            models_failed = True
            logger.warning(f"[{request_id}] Both models failed")

        # ──────────────────────────────────────────────
        # 4. Gemini AI analysis and decision
        # ──────────────────────────────────────────────
        gemini_result = None
        status = "success"

        try:
            gemini_result = gemini_service.analyze_and_decide(
                weather_data=weather_data,
                xgboost_result=xgboost_result,
                rl_result=rl_result,
                latitude=latitude,
                longitude=longitude,
                models_failed=models_failed,
            )
            logger.info(
                f"[{request_id}] Gemini analysis complete: "
                f"source={gemini_result.get('final_decision_source')}"
            )
        except Exception as e:
            logger.error(f"[{request_id}] Gemini analysis failed: {e}")
            # Fallback: use best available model prediction
            gemini_result = _build_fallback_gemini_response(
                xgboost_result, rl_result
            )
            status = "fallback_used"

        if models_failed and gemini_result:
            status = "fallback_used"

        # ──────────────────────────────────────────────
        # 5. Build final response
        # ──────────────────────────────────────────────
        response = {
            "location": {
                "lat": latitude,
                "lon": longitude,
            },
            "weather_data": weather_data,
            "models": {
                "xgboost": xgboost_result or {
                    "prediction": None,
                    "probability": None,
                    "confidence": None,
                },
                "rl": rl_result or {
                    "prediction": None,
                    "probability": None,
                    "confidence": None,
                },
            },
            "gemini": gemini_result or {
                "analysis": "Gemini analysis unavailable",
                "final_decision_source": "none",
                "final_prediction": "Unknown",
                "confidence": 0.0,
            },
            "status": status,
        }

        logger.info(
            f"[{request_id}] Prediction complete - "
            f"Status: {status}, "
            f"Final: {response['gemini'].get('final_prediction')}"
        )

        return jsonify(response), 200

    except Exception as e:
        logger.exception(f"[{request_id}] Unexpected error: {e}")
        return jsonify({
            "error": "Internal server error",
            "details": str(e),
            "status": "error",
        }), 500


def _build_fallback_gemini_response(xgboost_result, rl_result):
    """Build a fallback response when Gemini is unavailable."""
    if xgboost_result and rl_result:
        # Pick the one with higher confidence
        if (xgboost_result.get("confidence", 0) >=
                rl_result.get("confidence", 0)):
            source = "xgboost"
            best = xgboost_result
        else:
            source = "rl"
            best = rl_result
    elif xgboost_result:
        source = "xgboost"
        best = xgboost_result
    elif rl_result:
        source = "rl"
        best = rl_result
    else:
        return {
            "analysis": "All prediction systems unavailable",
            "final_decision_source": "none",
            "final_prediction": "Unknown",
            "confidence": 0.0,
        }

    return {
        "analysis": (
            f"Gemini unavailable. Using {source} model prediction "
            f"as fallback."
        ),
        "final_decision_source": source,
        "final_prediction": best.get("prediction", "Unknown"),
        "confidence": best.get("confidence", 0.0),
    }


if __name__ == "__main__":
    port = int(os.getenv("FLASK_PORT", 5000))
    debug = os.getenv("FLASK_DEBUG", "false").lower() == "true"

    logger.info(f"Starting Flood Prediction API on port {port}")
    app.run(host="0.0.0.0", port=port, debug=debug)
