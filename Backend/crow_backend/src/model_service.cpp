/**
 * Model Service - Implementation
 * Loads XGBoost and RL models; provides heuristic fallback
 * when models are unavailable.
 */

#include "model_service.h"
#include <iostream>
#include <fstream>
#include <cmath>
#include <algorithm>
#include <numeric>
#include <stdexcept>

// Feature indices (must match Python version)
enum FeatureIndex {
    AVG_TEMPERATURE = 0,
    MAX_TEMPERATURE = 1,
    MIN_TEMPERATURE = 2,
    TOTAL_PRECIPITATION = 3,
    AVG_PRECIPITATION = 4,
    MAX_DAILY_PRECIPITATION = 5,
    AVG_HUMIDITY = 6,
    MAX_WIND_SPEED = 7,
    AVG_SOIL_MOISTURE = 8,
    PRECIPITATION_TREND = 9,
    TEMP_RANGE = 10,
    CONSECUTIVE_RAIN_DAYS = 11,
    NUM_FEATURES = 12
};


ModelService::ModelService()
    : xgboost_loaded_(false), rl_loaded_(false) {
    load_models();
}


void ModelService::load_models() {
    // Attempt to load XGBoost model
    std::string xgb_path = "models/xgboost_flood_model.json";
    std::ifstream xgb_file(xgb_path);
    if (xgb_file.good()) {
        // In production, load via xgboost C API
        // For now, mark as loaded if file exists
        std::cout << "XGBoost model file found at " << xgb_path
                  << std::endl;
        // xgboost_loaded_ = true;
        // TODO: Integrate xgboost C API for native loading
    } else {
        std::cout << "XGBoost model not found at " << xgb_path
                  << ". Using heuristic fallback." << std::endl;
    }

    // Attempt to load RL model
    std::string rl_path = "models/rl_flood_model.pth";
    std::ifstream rl_file(rl_path);
    if (rl_file.good()) {
        std::cout << "RL model file found at " << rl_path
                  << std::endl;
        // rl_loaded_ = true;
        // TODO: Integrate LibTorch for native loading
    } else {
        std::cout << "RL model not found at " << rl_path
                  << ". Using heuristic fallback." << std::endl;
    }
}


std::vector<double> ModelService::preprocess_weather_data(
    const json& weather_data
) {
    if (weather_data.empty() || !weather_data.is_array()) {
        throw std::runtime_error("No weather data to preprocess");
    }

    std::vector<double> temps_max, temps_min, temps_mean;
    std::vector<double> precipitations, humidities;
    std::vector<double> wind_speeds, soil_moistures;

    for (const auto& day : weather_data) {
        auto temp = day.value("temperature", json::object());
        auto precip = day.value("precipitation", json::object());
        auto humid = day.value("humidity", json::object());
        auto wind = day.value("wind_speed", json::object());
        auto soil = day.value("soil_moisture", json::object());

        auto get_val = [](const json& obj,
                         const std::string& key,
                         double def = 0.0) -> double {
            if (obj.contains(key) && !obj[key].is_null()) {
                return obj[key].get<double>();
            }
            return def;
        };

        temps_max.push_back(get_val(temp, "max"));
        temps_min.push_back(get_val(temp, "min"));
        temps_mean.push_back(get_val(temp, "mean"));
        precipitations.push_back(get_val(precip, "total"));
        humidities.push_back(get_val(humid, "mean"));
        wind_speeds.push_back(get_val(wind, "max"));
        soil_moistures.push_back(get_val(soil, "mean"));
    }

    // Compute aggregate features
    auto mean = [](const std::vector<double>& v) -> double {
        if (v.empty()) return 0.0;
        return std::accumulate(v.begin(), v.end(), 0.0) / v.size();
    };

    double avg_temp = mean(temps_mean);
    double max_temp = temps_max.empty() ? 0.0 :
        *std::max_element(temps_max.begin(), temps_max.end());
    double min_temp = temps_min.empty() ? 0.0 :
        *std::min_element(temps_min.begin(), temps_min.end());
    double total_precip = std::accumulate(
        precipitations.begin(), precipitations.end(), 0.0
    );
    double avg_precip = mean(precipitations);
    double max_daily_precip = precipitations.empty() ? 0.0 :
        *std::max_element(
            precipitations.begin(), precipitations.end()
        );
    double avg_humidity = mean(humidities);
    double max_wind = wind_speeds.empty() ? 0.0 :
        *std::max_element(
            wind_speeds.begin(), wind_speeds.end()
        );
    double avg_soil = mean(soil_moistures);

    // Precipitation trend (simple linear regression slope)
    double precip_trend = 0.0;
    if (precipitations.size() > 1) {
        size_t n = precipitations.size();
        double sum_x = 0, sum_y = 0, sum_xy = 0, sum_x2 = 0;
        for (size_t i = 0; i < n; ++i) {
            double x = static_cast<double>(i);
            sum_x += x;
            sum_y += precipitations[i];
            sum_xy += x * precipitations[i];
            sum_x2 += x * x;
        }
        double denom = n * sum_x2 - sum_x * sum_x;
        if (denom != 0) {
            precip_trend = (n * sum_xy - sum_x * sum_y) / denom;
        }
    }

    double temp_range = max_temp - min_temp;

    // Consecutive rain days
    int consecutive_rain = 0;
    int max_consecutive = 0;
    for (double p : precipitations) {
        if (p > 0.1) {
            consecutive_rain++;
            max_consecutive =
                std::max(max_consecutive, consecutive_rain);
        } else {
            consecutive_rain = 0;
        }
    }

    std::vector<double> features = {
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
        static_cast<double>(max_consecutive)
    };

    std::cout << "Preprocessed " << features.size()
              << " features: total_precip="
              << total_precip << "mm, avg_humidity="
              << avg_humidity << "%" << std::endl;

    return features;
}


json ModelService::predict_xgboost(
    const std::vector<double>& features
) {
    if (xgboost_loaded_) {
        // TODO: Run actual XGBoost model inference here
        // Using xgboost C API: XGBoosterPredict(...)
    }

    // Heuristic fallback
    return heuristic_prediction(features, "xgboost");
}


json ModelService::predict_rl(
    const std::vector<double>& features
) {
    if (rl_loaded_) {
        // TODO: Run actual RL model inference here
        // Using LibTorch: torch::jit::load(...)
    }

    // Heuristic fallback
    return heuristic_prediction(features, "rl");
}


json ModelService::heuristic_prediction(
    const std::vector<double>& features,
    const std::string& model_name
) {
    if (features.size() < NUM_FEATURES) {
        return {
            {"prediction", "Unknown"},
            {"probability", 0.5},
            {"confidence", 0.0}
        };
    }

    double total_precip = features[TOTAL_PRECIPITATION];
    double max_daily_precip = features[MAX_DAILY_PRECIPITATION];
    double avg_humidity = features[AVG_HUMIDITY];
    double avg_soil_moisture = features[AVG_SOIL_MOISTURE];
    double precip_trend = features[PRECIPITATION_TREND];
    double consecutive_rain = features[CONSECUTIVE_RAIN_DAYS];

    // Scoring system (0-1 scale per factor with weights)
    // Precipitation: heavy rain >50mm total significant, >100mm critical
    double precip_score = std::min(total_precip / 100.0, 1.0);

    // Max daily precipitation: >30mm/day heavy, >50mm very heavy
    double max_precip_score = std::min(max_daily_precip / 50.0, 1.0);

    // Humidity: >80% is high
    double humidity_score = std::max(
        0.0, (avg_humidity - 50.0) / 50.0
    );
    humidity_score = std::min(humidity_score, 1.0);

    // Soil moisture: >0.3 m³/m³ is high
    double soil_score = std::min(avg_soil_moisture / 0.4, 1.0);

    // Consecutive rain days: >5 days is concerning
    double rain_days_score = std::min(consecutive_rain / 7.0, 1.0);

    // Precipitation trend (positive = increasing)
    double trend_score = std::max(
        0.0, std::min(precip_trend / 5.0, 1.0)
    );

    // Weighted sum
    double probability =
        precip_score * 0.30 +
        max_precip_score * 0.20 +
        humidity_score * 0.15 +
        soil_score * 0.10 +
        rain_days_score * 0.15 +
        trend_score * 0.10;

    probability = std::max(0.0, std::min(1.0, probability));

    // Slight variation for RL model
    if (model_name == "rl") {
        probability = probability * 0.95 + 0.025;
    }

    std::string prediction =
        (probability >= 0.5) ? "Flood" : "No Flood";

    // Confidence is lower for heuristic predictions
    double base_confidence = std::abs(probability - 0.5) * 2.0;
    double confidence = base_confidence * 0.7; // 30% penalty

    // Round to 4 decimal places
    probability = std::round(probability * 10000.0) / 10000.0;
    confidence = std::round(confidence * 10000.0) / 10000.0;

    std::cout << "Heuristic (" << model_name
              << ") prediction: prob=" << probability
              << ", conf=" << confidence << std::endl;

    return {
        {"prediction", prediction},
        {"probability", probability},
        {"confidence", confidence}
    };
}
