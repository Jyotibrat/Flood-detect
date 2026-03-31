/**
 * Gemini Service - Implementation
 * Handles Google Gemini API integration for flood analysis.
 */

#include "gemini_service.h"
#include <cpr/cpr.h>
#include <iostream>
#include <sstream>
#include <regex>
#include <algorithm>
#include <cmath>

static const std::string GEMINI_API_URL =
    "https://generativelanguage.googleapis.com/v1beta/"
    "models/gemini-2.0-flash:generateContent";


GeminiService::GeminiService(const std::string& api_key)
    : api_key_(api_key) {}


bool GeminiService::is_configured() const {
    return !api_key_.empty() && api_key_.size() > 10;
}


json GeminiService::analyze_and_decide(
    const json& weather_data,
    const json& xgboost_result,
    const json& rl_result,
    double latitude, double longitude,
    bool models_failed
) {
    if (!is_configured()) {
        std::cout << "Gemini API key not configured" << std::endl;
        return fallback_analysis(
            xgboost_result, rl_result, models_failed
        );
    }

    try {
        if (models_failed) {
            return independent_prediction(
                weather_data, latitude, longitude
            );
        } else {
            return validate_and_decide(
                weather_data, xgboost_result, rl_result,
                latitude, longitude
            );
        }
    } catch (const std::exception& e) {
        std::cerr << "Gemini analysis failed: " << e.what()
                  << std::endl;
        return fallback_analysis(
            xgboost_result, rl_result, models_failed
        );
    }
}


json GeminiService::validate_and_decide(
    const json& weather_data,
    const json& xgboost_result,
    const json& rl_result,
    double latitude, double longitude
) {
    std::string prompt = build_validation_prompt(
        weather_data, xgboost_result, rl_result,
        latitude, longitude
    );
    std::string response = call_gemini(prompt);
    if (response.empty()) {
        return fallback_analysis(xgboost_result, rl_result, false);
    }
    return parse_gemini_response(
        response, xgboost_result, rl_result
    );
}


json GeminiService::independent_prediction(
    const json& weather_data,
    double latitude, double longitude
) {
    std::string prompt = build_independent_prompt(
        weather_data, latitude, longitude
    );
    std::string response = call_gemini(prompt);
    if (response.empty()) {
        return {
            {"analysis", "Both ML models and Gemini unavailable."},
            {"final_decision_source", "none"},
            {"final_prediction", "Unknown"},
            {"confidence", 0.0}
        };
    }
    return parse_independent_response(response);
}


std::string GeminiService::summarize_weather(
    const json& weather_data
) {
    if (weather_data.empty()) return "No weather data available.";

    std::ostringstream ss;
    double total_precip = 0;
    int rain_days = 0;

    for (const auto& day : weather_data) {
        std::string date = day.value("date", "Unknown");
        auto temp = day.value("temperature", json::object());
        auto precip = day.value("precipitation", json::object());
        auto humid = day.value("humidity", json::object());
        auto wind = day.value("wind_speed", json::object());
        auto soil = day.value("soil_moisture", json::object());

        double p = 0;
        if (precip.contains("total") && !precip["total"].is_null())
            p = precip["total"].get<double>();
        total_precip += p;
        if (p > 0.1) rain_days++;

        ss << "  " << date << ": "
           << "Temp " << temp.value("min", 0.0)
           << "-" << temp.value("max", 0.0) << "C "
           << "(mean " << temp.value("mean", 0.0) << "C), "
           << "Precip " << p << "mm, "
           << "Humidity " << humid.value("mean", 0.0) << "%, "
           << "Wind " << wind.value("max", 0.0) << "km/h, "
           << "Soil " << soil.value("mean", 0.0) << "m3/m3\n";
    }

    ss << "\n  TOTALS: " << total_precip << "mm total precipitation, "
       << rain_days << " rain days out of "
       << weather_data.size();

    return ss.str();
}


std::string GeminiService::build_validation_prompt(
    const json& weather_data,
    const json& xgboost_result,
    const json& rl_result,
    double latitude, double longitude
) {
    std::string weather_summary = summarize_weather(weather_data);
    std::string xg_str = xgboost_result.is_null() ?
        "FAILED / Unavailable" : xgboost_result.dump();
    std::string rl_str = rl_result.is_null() ?
        "FAILED / Unavailable" : rl_result.dump();

    std::ostringstream ss;
    ss << "You are an expert hydrologist and flood prediction analyst.\n\n"
       << "TASK: Analyze weather data and ML model predictions for "
       << "flood risk at (" << latitude << ", " << longitude << ").\n\n"
       << "=== WEATHER DATA (Last 10 Days) ===\n"
       << weather_summary << "\n\n"
       << "=== MODEL PREDICTIONS ===\n"
       << "XGBoost: " << xg_str << "\n"
       << "RL: " << rl_str << "\n\n"
       << "=== TASKS ===\n"
       << "1. Analyze weather patterns for flood indicators\n"
       << "2. Evaluate each model prediction\n"
       << "3. Consider external factors\n"
       << "4. Make final decision\n\n"
       << "RESPOND IN THIS EXACT JSON FORMAT:\n"
       << "{\"analysis\": \"<2-3 sentences>\", "
       << "\"xgboost_reliable\": <true/false>, "
       << "\"rl_reliable\": <true/false>, "
       << "\"final_decision_source\": \"<xgboost|rl|gemini>\", "
       << "\"final_prediction\": \"<Flood|No Flood>\", "
       << "\"confidence\": <0.0-1.0>, "
       << "\"reasoning\": \"<brief>\"}\n\n"
       << "ONLY output valid JSON.";
    return ss.str();
}


std::string GeminiService::build_independent_prompt(
    const json& weather_data,
    double latitude, double longitude
) {
    std::string weather_summary = summarize_weather(weather_data);

    std::ostringstream ss;
    ss << "You are an expert hydrologist.\n\n"
       << "CRITICAL: Both ML models FAILED. "
       << "Provide independent flood risk assessment.\n\n"
       << "Location: (" << latitude << ", " << longitude << ")\n\n"
       << "=== WEATHER DATA (Last 10 Days) ===\n"
       << weather_summary << "\n\n"
       << "RESPOND IN THIS EXACT JSON FORMAT:\n"
       << "{\"analysis\": \"<2-3 sentences>\", "
       << "\"final_decision_source\": \"gemini\", "
       << "\"final_prediction\": \"<Flood|No Flood>\", "
       << "\"confidence\": <0.0-1.0>, "
       << "\"reasoning\": \"<brief>\"}\n\n"
       << "ONLY output valid JSON.";
    return ss.str();
}


std::string GeminiService::call_gemini(const std::string& prompt) {
    std::string url = GEMINI_API_URL + "?key=" + api_key_;

    json payload = {
        {"contents", {{
            {"parts", {{{"text", prompt}}}}
        }}},
        {"generationConfig", {
            {"temperature", 0.2},
            {"topP", 0.8},
            {"maxOutputTokens", 1024}
        }}
    };

    cpr::Response r = cpr::Post(
        cpr::Url{url},
        cpr::Header{{"Content-Type", "application/json"}},
        cpr::Body{payload.dump()},
        cpr::Timeout{30000}
    );

    if (r.status_code != 200) {
        std::cerr << "Gemini API error " << r.status_code
                  << ": " << r.text.substr(0, 500) << std::endl;
        return "";
    }

    try {
        json data = json::parse(r.text);
        auto& candidates = data["candidates"];
        if (candidates.empty()) return "";
        auto& parts = candidates[0]["content"]["parts"];
        if (parts.empty()) return "";
        return parts[0]["text"].get<std::string>();
    } catch (...) {
        std::cerr << "Failed to parse Gemini response" << std::endl;
        return "";
    }
}


json GeminiService::extract_json(const std::string& text) {
    // Try direct parse
    try {
        return json::parse(text);
    } catch (...) {}

    // Try to find JSON object in text
    size_t start = text.find('{');
    size_t end = text.rfind('}');
    if (start != std::string::npos && end != std::string::npos &&
        end > start) {
        try {
            return json::parse(
                text.substr(start, end - start + 1)
            );
        } catch (...) {}
    }

    return nullptr;
}


json GeminiService::parse_gemini_response(
    const std::string& response_text,
    const json& xgboost_result,
    const json& rl_result
) {
    json data = extract_json(response_text);
    if (data.is_null()) {
        return fallback_analysis(xgboost_result, rl_result, false);
    }

    std::string analysis = data.value("analysis",
                                       "Gemini analysis completed.");
    std::string source = data.value("final_decision_source",
                                     "gemini");
    std::string prediction = data.value("final_prediction",
                                         "Unknown");
    double confidence = data.value("confidence", 0.5);
    confidence = std::max(0.0, std::min(1.0, confidence));

    if (source != "xgboost" && source != "rl" &&
        source != "gemini") {
        source = "gemini";
    }

    if (prediction != "Flood" && prediction != "No Flood") {
        std::string lower = prediction;
        std::transform(lower.begin(), lower.end(),
                       lower.begin(), ::tolower);
        prediction = (lower.find("flood") != std::string::npos) ?
                     "Flood" : "No Flood";
    }

    return {
        {"analysis", analysis},
        {"final_decision_source", source},
        {"final_prediction", prediction},
        {"confidence", std::round(confidence * 10000) / 10000}
    };
}


json GeminiService::parse_independent_response(
    const std::string& response_text
) {
    json data = extract_json(response_text);
    if (data.is_null()) {
        return {
            {"analysis", "Gemini response could not be parsed."},
            {"final_decision_source", "gemini"},
            {"final_prediction", "Unknown"},
            {"confidence", 0.0}
        };
    }

    double conf = data.value("confidence", 0.5);
    conf = std::max(0.0, std::min(1.0, conf));

    return {
        {"analysis", data.value("analysis",
                                "Independent Gemini prediction.")},
        {"final_decision_source", "gemini"},
        {"final_prediction", data.value("final_prediction",
                                         "Unknown")},
        {"confidence", std::round(conf * 10000) / 10000}
    };
}


json GeminiService::fallback_analysis(
    const json& xgboost_result,
    const json& rl_result,
    bool models_failed
) {
    bool xg_valid = !xgboost_result.is_null() &&
                    xgboost_result.contains("prediction") &&
                    !xgboost_result["prediction"].is_null();
    bool rl_valid = !rl_result.is_null() &&
                    rl_result.contains("prediction") &&
                    !rl_result["prediction"].is_null();

    if (models_failed || (!xg_valid && !rl_valid)) {
        return {
            {"analysis", "All prediction systems unavailable."},
            {"final_decision_source", "none"},
            {"final_prediction", "Unknown"},
            {"confidence", 0.0}
        };
    }

    if (xg_valid && rl_valid) {
        double xg_c = xgboost_result.value("confidence", 0.0);
        double rl_c = rl_result.value("confidence", 0.0);
        bool agree = xgboost_result.value("prediction", "") ==
                     rl_result.value("prediction", "");

        std::string src = (xg_c >= rl_c) ? "xgboost" : "rl";
        const json& best = (xg_c >= rl_c) ?
                           xgboost_result : rl_result;
        double conf = std::max(xg_c, rl_c);
        if (!agree) conf *= 0.8;

        std::string msg = agree ?
            "Both models agree. Using " + src + "." :
            "Models disagree. Using " + src + " (higher confidence).";
        msg += " Gemini validation unavailable.";

        return {
            {"analysis", msg},
            {"final_decision_source", src},
            {"final_prediction", best.value("prediction", "Unknown")},
            {"confidence", std::round(conf * 10000) / 10000}
        };
    }

    if (xg_valid) {
        return {
            {"analysis", "Only XGBoost available. Gemini unavailable."},
            {"final_decision_source", "xgboost"},
            {"final_prediction",
             xgboost_result.value("prediction", "Unknown")},
            {"confidence",
             std::round(xgboost_result.value("confidence", 0.0)
                        * 0.8 * 10000) / 10000}
        };
    }

    return {
        {"analysis", "Only RL available. Gemini unavailable."},
        {"final_decision_source", "rl"},
        {"final_prediction", rl_result.value("prediction", "Unknown")},
        {"confidence",
         std::round(rl_result.value("confidence", 0.0)
                    * 0.8 * 10000) / 10000}
    };
}
