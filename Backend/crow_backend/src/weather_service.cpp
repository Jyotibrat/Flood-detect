/**
 * Weather Service - Implementation
 * Uses cpr (C++ Requests) for HTTP calls to Open-Meteo API.
 */

#include "weather_service.h"
#include <cpr/cpr.h>
#include <iostream>
#include <sstream>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <stdexcept>
#include <algorithm>
#include <numeric>

// API URLs
static const std::string OPEN_METEO_ARCHIVE_URL =
    "https://archive-api.open-meteo.com/v1/archive";
static const std::string OPEN_METEO_FORECAST_URL =
    "https://api.open-meteo.com/v1/forecast";
static const std::string IP_GEOLOCATION_URL =
    "http://ip-api.com/json";


WeatherService::WeatherService(int timeout_seconds)
    : timeout_(timeout_seconds) {}


json WeatherService::http_get(const std::string& url) {
    cpr::Response r = cpr::Get(
        cpr::Url{url},
        cpr::Timeout{timeout_ * 1000},
        cpr::Header{
            {"User-Agent", "FloodPredictionBackend/1.0"},
            {"Accept", "application/json"}
        }
    );

    if (r.status_code != 200) {
        throw std::runtime_error(
            "HTTP request failed with status " +
            std::to_string(r.status_code) + ": " + r.text
        );
    }

    return json::parse(r.text);
}


json WeatherService::get_location_from_ip(const std::string& ip) {
    std::string url = IP_GEOLOCATION_URL;
    if (!ip.empty() && ip != "127.0.0.1" &&
        ip != "::1" && ip != "localhost") {
        url = IP_GEOLOCATION_URL + "/" + ip;
    }

    json data = http_get(url);

    if (data.value("status", "") == "fail") {
        throw std::runtime_error(
            "IP geolocation failed: " +
            data.value("message", "unknown error")
        );
    }

    return {
        {"latitude", data.value("lat", 0.0)},
        {"longitude", data.value("lon", 0.0)},
        {"city", data.value("city", "Unknown")},
        {"country", data.value("country", "Unknown")}
    };
}


json WeatherService::fetch_historical_weather(
    double latitude, double longitude, int days
) {
    // Calculate date range
    auto now = std::chrono::system_clock::now();
    auto yesterday = now - std::chrono::hours(24);
    auto start = now - std::chrono::hours(24 * days);

    auto format_date = [](auto tp) -> std::string {
        auto time = std::chrono::system_clock::to_time_t(tp);
        std::tm tm_buf;
#ifdef _WIN32
        gmtime_s(&tm_buf, &time);
#else
        gmtime_r(&time, &tm_buf);
#endif
        std::ostringstream oss;
        oss << std::put_time(&tm_buf, "%Y-%m-%d");
        return oss.str();
    };

    std::string start_date = format_date(start);
    std::string end_date = format_date(yesterday);

    std::cout << "Fetching weather data from " << start_date
              << " to " << end_date
              << " for (" << latitude << ", " << longitude << ")"
              << std::endl;

    // Build URL for Archive API
    std::string daily_vars =
        "temperature_2m_max,temperature_2m_min,temperature_2m_mean,"
        "precipitation_sum,rain_sum,windspeed_10m_max,"
        "et0_fao_evapotranspiration";
    std::string hourly_vars =
        "relative_humidity_2m,soil_moisture_0_to_7cm";

    std::ostringstream url;
    url << OPEN_METEO_ARCHIVE_URL
        << "?latitude=" << latitude
        << "&longitude=" << longitude
        << "&start_date=" << start_date
        << "&end_date=" << end_date
        << "&daily=" << daily_vars
        << "&hourly=" << hourly_vars
        << "&timezone=UTC";

    try {
        json data = http_get(url.str());
        json records = parse_weather_response(data);
        if (!records.empty()) {
            std::cout << "Successfully fetched "
                      << records.size()
                      << " days of weather data" << std::endl;
            return records;
        }
    } catch (const std::exception& e) {
        std::cerr << "Archive API failed: " << e.what()
                  << ". Trying forecast API fallback..." << std::endl;
    }

    // Fallback to forecast API
    return fetch_from_forecast_api(latitude, longitude, days);
}


json WeatherService::fetch_from_forecast_api(
    double latitude, double longitude, int days
) {
    std::ostringstream url;
    url << OPEN_METEO_FORECAST_URL
        << "?latitude=" << latitude
        << "&longitude=" << longitude
        << "&past_days=" << days
        << "&daily=temperature_2m_max,temperature_2m_min,"
           "precipitation_sum,rain_sum,windspeed_10m_max"
        << "&hourly=relative_humidity_2m,soil_moisture_0_to_7cm"
        << "&timezone=UTC"
        << "&forecast_days=0";

    json data = http_get(url.str());
    return parse_weather_response(data);
}


json WeatherService::parse_weather_response(const json& data) {
    json records = json::array();

    if (!data.contains("daily")) {
        return records;
    }

    const json& daily = data["daily"];
    if (!daily.contains("time")) {
        return records;
    }

    const auto& dates = daily["time"];

    // Compute daily averages for hourly fields
    std::map<std::string, double> humidity_daily;
    std::map<std::string, double> soil_moisture_daily;

    if (data.contains("hourly")) {
        const json& hourly = data["hourly"];

        if (hourly.contains("time") &&
            hourly.contains("relative_humidity_2m")) {
            std::vector<std::string> times;
            std::vector<double> values;

            for (size_t i = 0; i < hourly["time"].size(); ++i) {
                times.push_back(hourly["time"][i].get<std::string>());
                if (!hourly["relative_humidity_2m"][i].is_null()) {
                    values.push_back(
                        hourly["relative_humidity_2m"][i].get<double>()
                    );
                } else {
                    values.push_back(-9999.0); // sentinel
                }
            }
            humidity_daily = compute_daily_averages(times, values);
        }

        if (hourly.contains("time") &&
            hourly.contains("soil_moisture_0_to_7cm")) {
            std::vector<std::string> times;
            std::vector<double> values;

            for (size_t i = 0; i < hourly["time"].size(); ++i) {
                times.push_back(hourly["time"][i].get<std::string>());
                if (!hourly["soil_moisture_0_to_7cm"][i].is_null()) {
                    values.push_back(
                        hourly["soil_moisture_0_to_7cm"][i].get<double>()
                    );
                } else {
                    values.push_back(-9999.0);
                }
            }
            soil_moisture_daily =
                compute_daily_averages(times, values);
        }
    }

    for (size_t i = 0; i < dates.size(); ++i) {
        std::string date_str = dates[i].get<std::string>();

        json temp_max = safe_get(daily, "temperature_2m_max", i);
        json temp_min = safe_get(daily, "temperature_2m_min", i);
        json temp_mean = safe_get(daily, "temperature_2m_mean", i);

        // Compute mean if not available directly
        if (temp_mean.is_null() &&
            !temp_max.is_null() && !temp_min.is_null()) {
            double mean = (temp_max.get<double>() +
                          temp_min.get<double>()) / 2.0;
            temp_mean = std::round(mean * 10.0) / 10.0;
        }

        // Get humidity and soil moisture
        json humidity_val = nullptr;
        auto h_it = humidity_daily.find(date_str);
        if (h_it != humidity_daily.end()) {
            humidity_val = std::round(h_it->second * 100.0) / 100.0;
        }

        json soil_val = nullptr;
        auto s_it = soil_moisture_daily.find(date_str);
        if (s_it != soil_moisture_daily.end()) {
            soil_val = std::round(s_it->second * 10000.0) / 10000.0;
        }

        json record = {
            {"date", date_str},
            {"temperature", {
                {"max", temp_max},
                {"min", temp_min},
                {"mean", temp_mean},
                {"unit", "°C"}
            }},
            {"precipitation", {
                {"total", safe_get(daily, "precipitation_sum", i)},
                {"rain", safe_get(daily, "rain_sum", i)},
                {"unit", "mm"}
            }},
            {"humidity", {
                {"mean", humidity_val},
                {"unit", "%"}
            }},
            {"wind_speed", {
                {"max", safe_get(daily, "windspeed_10m_max", i)},
                {"unit", "km/h"}
            }},
            {"soil_moisture", {
                {"mean", soil_val},
                {"unit", "m³/m³"}
            }},
            {"evapotranspiration", {
                {"value", safe_get(
                    daily, "et0_fao_evapotranspiration", i)},
                {"unit", "mm"}
            }}
        };

        records.push_back(record);
    }

    return records;
}


std::map<std::string, double> WeatherService::compute_daily_averages(
    const std::vector<std::string>& times,
    const std::vector<double>& values
) {
    std::map<std::string, std::vector<double>> daily_vals;

    for (size_t i = 0; i < times.size() && i < values.size(); ++i) {
        if (values[i] < -9998.0) continue; // skip sentinels

        std::string date_key = times[i].substr(0, 10);
        daily_vals[date_key].push_back(values[i]);
    }

    std::map<std::string, double> result;
    for (const auto& [date, vals] : daily_vals) {
        if (!vals.empty()) {
            double sum = std::accumulate(
                vals.begin(), vals.end(), 0.0
            );
            result[date] = sum / vals.size();
        }
    }

    return result;
}


json WeatherService::safe_get(
    const json& data, const std::string& key, size_t index
) {
    if (!data.contains(key)) return nullptr;
    const auto& arr = data[key];
    if (index >= arr.size()) return nullptr;
    if (arr[index].is_null()) return nullptr;
    return arr[index];
}
