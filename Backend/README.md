# Flood Prediction Backend

Production-ready backend system for a Flood Prediction Mobile Application with **dual implementation**: C++ (Crow) and Python (Flask).

Both backends have **identical API structure, logic, and responses**.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Flutter App                     │
│              (Sends lat/lon)                     │
└──────────────────┬──────────────────────────────┘
                   │ POST /predict
                   ▼
┌─────────────────────────────────────────────────┐
│           Backend (Flask or Crow)                │
│                                                  │
│  ┌──────────────┐  ┌────────────┐  ┌──────────┐ │
│  │ Weather Svc  │  │ Model Svc  │  │ Gemini   │ │
│  │ (Open-Meteo) │  │ XGB + RL   │  │ Service  │ │
│  └──────┬───────┘  └──────┬─────┘  └────┬─────┘ │
│         │                 │              │       │
│         └────────┬────────┘              │       │
│                  ▼                       ▼       │
│         Feature Engineering    AI Validation     │
│                  │              & Decision       │
│                  └──────┬───────┘                │
│                         ▼                        │
│                  Final Response                  │
└─────────────────────────────────────────────────┘
```

## API Reference

### `GET /health`
Health check endpoint.

### `POST /predict`

**Request:**
```json
{
  "latitude": 28.6139,
  "longitude": 77.2090
}
```

**Response:**
```json
{
  "location": { "lat": 28.6139, "lon": 77.209 },
  "weather_data": [ ... ],
  "models": {
    "xgboost": {
      "prediction": "No Flood",
      "probability": 0.2345,
      "confidence": 0.531
    },
    "rl": {
      "prediction": "No Flood",
      "probability": 0.2478,
      "confidence": 0.4989
    }
  },
  "gemini": {
    "analysis": "Weather analysis indicates low flood risk...",
    "final_decision_source": "xgboost",
    "final_prediction": "No Flood",
    "confidence": 0.85
  },
  "status": "success"
}
```

---

## Flask Backend Setup

### Prerequisites
- Python 3.9+
- pip

### Installation

```bash
cd Backend/flask_backend

# Create virtual environment
python -m venv venv

# Activate (Windows)
venv\Scripts\activate

# Activate (Linux/Mac)
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### Configuration

```bash
# Copy env template
cp .env.example .env

# Edit .env and add your Gemini API key
# GEMINI_API_KEY=your_key_here
```

### Running

```bash
# Development
python app.py

# Production
gunicorn -w 4 -b 0.0.0.0:5000 app:app
```

### Optional: ML Models

```bash
# Uncomment in requirements.txt and install:
pip install xgboost torch

# Place model files in:
#   Backend/flask_backend/models/xgboost_flood_model.json
#   Backend/flask_backend/models/rl_flood_model.pth
```

---

## C++ Crow Backend Setup

### Prerequisites
- CMake 3.15+
- C++17 compiler (GCC 8+, Clang 7+, MSVC 2019+)
- Git (for FetchContent)

### Building

```bash
cd Backend/crow_backend

# Create build directory
mkdir build && cd build

# Configure (dependencies auto-downloaded)
cmake ..

# Build
cmake --build . --config Release

# Or on Linux/Mac:
make -j$(nproc)
```

### Running

```bash
# Set environment variables
export GEMINI_API_KEY=your_key_here
export CROW_PORT=5000

# Run
./flood_prediction_server
```

### Optional: Place model files

```
Backend/crow_backend/models/xgboost_flood_model.json
Backend/crow_backend/models/rl_flood_model.pth
```

---

## Decision Logic

```
Priority Chain:
1. Valid ML model prediction (verified by Gemini) ← BEST
2. Gemini-corrected prediction                   ← OVERRIDE
3. Gemini independent prediction                 ← FAILSAFE

Fallback (no Gemini):
- Models agree → use higher confidence model
- Models disagree → use higher confidence model (penalized)
- One model fails → use surviving model (penalized)
- Both fail → Unknown
```

## Features

| Feature | Flask | Crow |
|---------|-------|------|
| Weather API (Open-Meteo) | ✅ | ✅ |
| IP Geolocation Fallback | ✅ | ✅ |
| XGBoost Model | ✅ | ✅ |
| RL Model | ✅ | ✅ |
| Heuristic Fallback | ✅ | ✅ |
| Gemini AI Analysis | ✅ | ✅ |
| Multi-tier Failsafe | ✅ | ✅ |
| Request Logging | ✅ | ✅ |
| Input Validation | ✅ | ✅ |
| CORS Support | ✅ | ✅ |
| Multithreaded | gunicorn | Crow native |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GEMINI_API_KEY` | (none) | Google Gemini API key |
| `FLASK_PORT` / `CROW_PORT` | 5000 | Server port |
| `FLASK_DEBUG` | false | Debug mode (Flask only) |

## Testing

```bash
# Test the predict endpoint
curl -X POST http://localhost:5000/predict \
  -H "Content-Type: application/json" \
  -d '{"latitude": 28.6139, "longitude": 77.2090}'

# Test health check
curl http://localhost:5000/health

# Test without coordinates (IP geolocation)
curl -X POST http://localhost:5000/predict \
  -H "Content-Type: application/json" \
  -d '{}'
```
