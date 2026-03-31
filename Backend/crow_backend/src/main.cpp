/**
 * Flood Prediction Backend - C++ Crow Application
 * Main entry point for the Crow-based flood prediction API.
 *
 * Build: mkdir build && cd build && cmake .. && make
 * Run:   ./flood_prediction_server
 */

#include "crow_all.h"
#include "weather_service.h"
#include "model_service.h"
#include "gemini_service.h"

#include <nlohmann/json.hpp>
#include <iostream>
#include <fstream>
#include <chrono>
#include <cstdlib>
#include <string>
#include <sstream>
#include <iomanip>

using json = nlohmann::json;

// ─────────────────────────────────────────────────
// Logger helper
// ─────────────────────────────────────────────────
std::string get_timestamp() {
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    std::tm tm_buf;
#ifdef _WIN32
    localtime_s(&tm_buf, &time);
#else
    localtime_r(&time, &tm_buf);
#endif
    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y-%m-%d %H:%M:%S");
    return oss.str();
}

std::string generate_request_id() {
    auto now = std::chrono::system_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::microseconds>(
        now.time_since_epoch()
    ).count();
    return std::to_string(ms);
}

void log_info(const std::string& request_id, const std::string& msg) {
    std::cout << get_timestamp() << " [INFO] [" << request_id << "] "
              << msg << std::endl;
}

void log_error(const std::string& request_id, const std::string& msg) {
    std::cerr << get_timestamp() << " [ERROR] [" << request_id << "] "
              << msg << std::endl;
}

void log_warning(const std::string& request_id, const std::string& msg) {
    std::cout << get_timestamp() << " [WARN] [" << request_id << "] "
              << msg << std::endl;
}

// ─────────────────────────────────────────────────
// Fallback Gemini response builder
// ─────────────────────────────────────────────────
json build_fallback_gemini_response(
    const json& xgboost_result,
    const json& rl_result
) {
    bool xg_valid = !xgboost_result.is_null() &&
                    xgboost_result.contains("prediction") &&
                    !xgboost_result["prediction"].is_null();
    bool rl_valid = !rl_result.is_null() &&
                    rl_result.contains("prediction") &&
                    !rl_result["prediction"].is_null();

    if (xg_valid && rl_valid) {
        double xg_conf = xgboost_result.value("confidence", 0.0);
        double rl_conf = rl_result.value("confidence", 0.0);

        std::string source = (xg_conf >= rl_conf) ? "xgboost" : "rl";
        const json& best = (xg_conf >= rl_conf) ?
                           xgboost_result : rl_result;

        return {
            {"analysis", "Gemini unavailable. Using " + source +
                         " model prediction as fallback."},
            {"final_decision_source", source},
            {"final_prediction", best.value("prediction", "Unknown")},
            {"confidence", best.value("confidence", 0.0)}
        };
    } else if (xg_valid) {
        return {
            {"analysis", "Gemini unavailable. Using XGBoost as fallback."},
            {"final_decision_source", "xgboost"},
            {"final_prediction",
             xgboost_result.value("prediction", "Unknown")},
            {"confidence", xgboost_result.value("confidence", 0.0)}
        };
    } else if (rl_valid) {
        return {
            {"analysis", "Gemini unavailable. Using RL as fallback."},
            {"final_decision_source", "rl"},
            {"final_prediction", rl_result.value("prediction", "Unknown")},
            {"confidence", rl_result.value("confidence", 0.0)}
        };
    }

    return {
        {"analysis", "All prediction systems unavailable"},
        {"final_decision_source", "none"},
        {"final_prediction", "Unknown"},
        {"confidence", 0.0}
    };
}


int main() {
    // ─── Load configuration ─────────────────────
    std::string gemini_api_key;
    const char* env_key = std::getenv("GEMINI_API_KEY");
    if (env_key) {
        gemini_api_key = env_key;
    }

    int port = 5000;
    const char* env_port = std::getenv("CROW_PORT");
    if (env_port) {
        try {
            port = std::stoi(env_port);
        } catch (...) {
            port = 5000;
        }
    }

    // ─── Initialize services ────────────────────
    WeatherService weather_service;
    ModelService model_service;
    GeminiService gemini_service(gemini_api_key);

    std::cout << get_timestamp()
              << " [INFO] Services initialized" << std::endl;
    std::cout << get_timestamp()
              << " [INFO] XGBoost loaded: "
              << (model_service.is_xgboost_loaded() ? "yes" : "no (heuristic fallback)")
              << std::endl;
    std::cout << get_timestamp()
              << " [INFO] RL loaded: "
              << (model_service.is_rl_loaded() ? "yes" : "no (heuristic fallback)")
              << std::endl;
    std::cout << get_timestamp()
              << " [INFO] Gemini configured: "
              << (gemini_service.is_configured() ? "yes" : "no")
              << std::endl;

    // ─── Set up Crow app ────────────────────────
    crow::SimpleApp app;

    // ─── Health Check Endpoint ──────────────────
    CROW_ROUTE(app, "/health").methods("GET"_method)(
        [&]() {
            json response = {
                {"status", "healthy"},
                {"timestamp", get_timestamp()},
                {"version", "1.0.0"},
                {"services", {
                    {"weather", "operational"},
                    {"models", {
                        {"xgboost", model_service.is_xgboost_loaded()},
                        {"rl", model_service.is_rl_loaded()}
                    }},
                    {"gemini", gemini_service.is_configured()}
                }}
            };
            return crow::response(200, response.dump(2));
        }
    );

    // ─── Main Prediction Endpoint ───────────────
    CROW_ROUTE(app, "/predict").methods("POST"_method)(
        [&](const crow::request& req) {
            std::string request_id = generate_request_id();
            log_info(request_id, "Received prediction request");

            crow::response res;
            res.add_header("Content-Type", "application/json");

            try {
                // ── 1. Parse location ───────────
                double latitude = 0.0, longitude = 0.0;
                bool coords_provided = false;

                json body;
                try {
                    if (!req.body.empty()) {
                        body = json::parse(req.body);
                    }
                } catch (const json::parse_error& e) {
                    log_error(request_id,
                              "Invalid JSON body: " +
                              std::string(e.what()));
                    res.code = 400;
                    res.body = json({
                        {"error", "Invalid JSON in request body"},
                        {"status", "error"}
                    }).dump();
                    return res;
                }

                if (body.contains("latitude") &&
                    body.contains("longitude") &&
                    !body["latitude"].is_null() &&
                    !body["longitude"].is_null()) {
                    try {
                        latitude = body["latitude"].get<double>();
                        longitude = body["longitude"].get<double>();
                        coords_provided = true;
                    } catch (...) {
                        res.code = 400;
                        res.body = json({
                            {"error",
                             "Invalid latitude or longitude values. "
                             "Must be numeric."},
                            {"status", "error"}
                        }).dump();
                        return res;
                    }
                }

                if (coords_provided) {
                    if (latitude < -90 || latitude > 90 ||
                        longitude < -180 || longitude > 180) {
                        res.code = 400;
                        res.body = json({
                            {"error",
                             "Latitude must be between -90 and 90, "
                             "longitude between -180 and 180."},
                            {"status", "error"}
                        }).dump();
                        return res;
                    }
                } else {
                    log_info(request_id,
                             "No coordinates provided, "
                             "using IP geolocation");
                    try {
                        auto geo =
                            weather_service.get_location_from_ip();
                        latitude = geo["latitude"];
                        longitude = geo["longitude"];
                        log_info(request_id,
                                 "IP geolocation resolved: (" +
                                 std::to_string(latitude) + ", " +
                                 std::to_string(longitude) + ")");
                    } catch (const std::exception& e) {
                        log_error(request_id,
                                  "IP geolocation failed: " +
                                  std::string(e.what()));
                        res.code = 400;
                        res.body = json({
                            {"error",
                             "Could not determine location. "
                             "Please provide latitude and longitude."},
                            {"status", "error"}
                        }).dump();
                        return res;
                    }
                }

                log_info(request_id,
                         "Processing prediction for (" +
                         std::to_string(latitude) + ", " +
                         std::to_string(longitude) + ")");

                // ── 2. Fetch weather data ──────
                json weather_data = json::array();
                try {
                    weather_data =
                        weather_service.fetch_historical_weather(
                            latitude, longitude
                        );
                    log_info(request_id,
                             "Fetched " +
                             std::to_string(weather_data.size()) +
                             " days of weather data");
                } catch (const std::exception& e) {
                    log_error(request_id,
                              "Weather data fetch failed: " +
                              std::string(e.what()));
                }

                // ── 3. Run ML models ───────────
                json xgboost_result = nullptr;
                json rl_result = nullptr;
                bool models_failed = false;

                std::vector<double> features;
                try {
                    features =
                        model_service.preprocess_weather_data(
                            weather_data
                        );
                    log_info(request_id,
                             "Preprocessed " +
                             std::to_string(features.size()) +
                             " features for model input");
                } catch (const std::exception& e) {
                    log_error(request_id,
                              "Feature preprocessing failed: " +
                              std::string(e.what()));
                    models_failed = true;
                }

                if (!models_failed && !features.empty()) {
                    // XGBoost
                    try {
                        xgboost_result =
                            model_service.predict_xgboost(features);
                        log_info(request_id,
                                 "XGBoost prediction: " +
                                 xgboost_result.dump());
                    } catch (const std::exception& e) {
                        log_error(request_id,
                                  "XGBoost prediction failed: " +
                                  std::string(e.what()));
                    }

                    // RL
                    try {
                        rl_result =
                            model_service.predict_rl(features);
                        log_info(request_id,
                                 "RL prediction: " +
                                 rl_result.dump());
                    } catch (const std::exception& e) {
                        log_error(request_id,
                                  "RL prediction failed: " +
                                  std::string(e.what()));
                    }
                }

                if (xgboost_result.is_null() &&
                    rl_result.is_null()) {
                    models_failed = true;
                    log_warning(request_id, "Both models failed");
                }

                // ── 4. Gemini AI analysis ──────
                json gemini_result = nullptr;
                std::string status = "success";

                try {
                    gemini_result =
                        gemini_service.analyze_and_decide(
                            weather_data,
                            xgboost_result,
                            rl_result,
                            latitude, longitude,
                            models_failed
                        );
                    if (!gemini_result.is_null()) {
                        log_info(request_id,
                                 "Gemini analysis complete: source=" +
                                 gemini_result.value(
                                     "final_decision_source",
                                     "unknown"
                                 ));
                    }
                } catch (const std::exception& e) {
                    log_error(request_id,
                              "Gemini analysis failed: " +
                              std::string(e.what()));
                    gemini_result =
                        build_fallback_gemini_response(
                            xgboost_result, rl_result
                        );
                    status = "fallback_used";
                }

                if (models_failed && !gemini_result.is_null()) {
                    status = "fallback_used";
                }

                // ── 5. Build response ──────────
                json xg_out = xgboost_result.is_null() ? json({
                    {"prediction", nullptr},
                    {"probability", nullptr},
                    {"confidence", nullptr}
                }) : xgboost_result;

                json rl_out = rl_result.is_null() ? json({
                    {"prediction", nullptr},
                    {"probability", nullptr},
                    {"confidence", nullptr}
                }) : rl_result;

                json gemini_out = gemini_result.is_null() ? json({
                    {"analysis", "Gemini analysis unavailable"},
                    {"final_decision_source", "none"},
                    {"final_prediction", "Unknown"},
                    {"confidence", 0.0}
                }) : gemini_result;

                json response = {
                    {"location", {
                        {"lat", latitude},
                        {"lon", longitude}
                    }},
                    {"weather_data", weather_data},
                    {"models", {
                        {"xgboost", xg_out},
                        {"rl", rl_out}
                    }},
                    {"gemini", gemini_out},
                    {"status", status}
                };

                log_info(request_id,
                         "Prediction complete - Status: " + status);

                res.code = 200;
                res.body = response.dump(2);
                return res;

            } catch (const std::exception& e) {
                log_error(request_id,
                          "Unexpected error: " +
                          std::string(e.what()));
                res.code = 500;
                res.body = json({
                    {"error", "Internal server error"},
                    {"details", e.what()},
                    {"status", "error"}
                }).dump();
                return res;
            }
        }
    );

    // ─── Start server ───────────────────────────
    std::cout << get_timestamp()
              << " [INFO] Starting Flood Prediction API on port "
              << port << std::endl;

    app.port(port)
       .multithreaded()
       .run();

    return 0;
}
