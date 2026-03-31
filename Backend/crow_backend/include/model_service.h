/**
 * Model Service - Header
 * Handles loading and running flood prediction models.
 */

#pragma once

#include <nlohmann/json.hpp>
#include <vector>
#include <string>

using json = nlohmann::json;

class ModelService {
public:
    ModelService();

    bool is_xgboost_loaded() const { return xgboost_loaded_; }
    bool is_rl_loaded() const { return rl_loaded_; }

    /**
     * Transform weather data JSON into feature vector.
     */
    std::vector<double> preprocess_weather_data(
        const json& weather_data
    );

    /**
     * Run XGBoost prediction (or heuristic fallback).
     */
    json predict_xgboost(const std::vector<double>& features);

    /**
     * Run RL prediction (or heuristic fallback).
     */
    json predict_rl(const std::vector<double>& features);

private:
    bool xgboost_loaded_;
    bool rl_loaded_;

    void load_models();

    /**
     * Statistical heuristic fallback for prediction.
     */
    json heuristic_prediction(
        const std::vector<double>& features,
        const std::string& model_name
    );
};
