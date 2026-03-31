/**
 * Weather Service - Header
 * Fetches historical weather data from Open-Meteo API
 * and provides IP-based geolocation fallback.
 */

#pragma once

#include <nlohmann/json.hpp>
#include <string>
#include <vector>
#include <map>

using json = nlohmann::json;

class WeatherService {
public:
    WeatherService(int timeout_seconds = 30);

    /**
     * Get latitude/longitude from IP address using ip-api.com.
     * Returns JSON with "latitude" and "longitude" keys.
     */
    json get_location_from_ip(const std::string& ip = "");

    /**
     * Fetch historical weather data for the last N days.
     * Returns JSON array of daily weather records.
     */
    json fetch_historical_weather(
        double latitude, double longitude, int days = 10
    );

private:
    int timeout_;

    /**
     * Fetch from Open-Meteo Forecast API as fallback.
     */
    json fetch_from_forecast_api(
        double latitude, double longitude, int days
    );

    /**
     * Parse Open-Meteo API response into structured records.
     */
    json parse_weather_response(const json& data);

    /**
     * Compute daily averages from hourly time series.
     */
    std::map<std::string, double> compute_daily_averages(
        const std::vector<std::string>& times,
        const std::vector<double>& values
    );

    /**
     * Safely get a numeric value from a JSON array.
     */
    static json safe_get(const json& data,
                         const std::string& key, size_t index);

    /**
     * Perform HTTP GET request and return JSON response.
     */
    json http_get(const std::string& url);
};
