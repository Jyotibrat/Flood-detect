import axios from 'axios';

// Weather API Configuration
// You can use OpenWeatherMap, WeatherAPI, or any other weather service
const WEATHER_API_KEY = 'YOUR_WEATHER_API_KEY'; // Replace with your actual API key
const WEATHER_API_BASE_URL = 'https://api.openweathermap.org/data/2.5';

// Your AI Model API Configuration
const FLOOD_PREDICTION_API_URL = 'http://your-ai-model-endpoint.com/api/predict';

/**
 * Fetch current weather data
 */
export const getCurrentWeather = async (latitude, longitude) => {
    try {
        const response = await axios.get(`${WEATHER_API_BASE_URL}/weather`, {
            params: {
                lat: latitude,
                lon: longitude,
                appid: WEATHER_API_KEY,
                units: 'metric',
            },
        });

        return {
            success: true,
            data: response.data,
        };
    } catch (error) {
        console.error('Error fetching current weather:', error);
        return {
            success: false,
            error: error.message,
        };
    }
};

/**
 * Fetch historical weather data (yesterday)
 */
export const getHistoricalWeather = async (latitude, longitude) => {
    try {
        // Get timestamp for yesterday
        const yesterday = Math.floor(Date.now() / 1000) - 86400; // 24 hours ago

        const response = await axios.get(`${WEATHER_API_BASE_URL}/onecall/timemachine`, {
            params: {
                lat: latitude,
                lon: longitude,
                dt: yesterday,
                appid: WEATHER_API_KEY,
                units: 'metric',
            },
        });

        return {
            success: true,
            data: response.data,
        };
    } catch (error) {
        console.error('Error fetching historical weather:', error);
        return {
            success: false,
            error: error.message,
        };
    }
};

/**
 * Fetch 5-day forecast
 */
export const getWeatherForecast = async (latitude, longitude) => {
    try {
        const response = await axios.get(`${WEATHER_API_BASE_URL}/forecast`, {
            params: {
                lat: latitude,
                lon: longitude,
                appid: WEATHER_API_KEY,
                units: 'metric',
            },
        });

        return {
            success: true,
            data: response.data,
        };
    } catch (error) {
        console.error('Error fetching weather forecast:', error);
        return {
            success: false,
            error: error.message,
        };
    }
};

/**
 * Predict flood based on weather data
 */
export const predictFlood = async (currentWeather, historicalWeather) => {
    try {
        // Prepare weather data for AI model
        const weatherData = {
            current: {
                temperature: currentWeather.main.temp,
                humidity: currentWeather.main.humidity,
                pressure: currentWeather.main.pressure,
                rainfall: currentWeather.rain?.['1h'] || 0,
                windSpeed: currentWeather.wind.speed,
                cloudiness: currentWeather.clouds.all,
            },
            yesterday: {
                temperature: historicalWeather.current.temp,
                humidity: historicalWeather.current.humidity,
                pressure: historicalWeather.current.pressure,
                rainfall: historicalWeather.current.rain?.['1h'] || 0,
                windSpeed: historicalWeather.current.wind_speed,
                cloudiness: historicalWeather.current.clouds,
            },
            location: {
                latitude: currentWeather.coord.lat,
                longitude: currentWeather.coord.lon,
                city: currentWeather.name,
            },
        };

        // Send to your AI model
        const response = await axios.post(FLOOD_PREDICTION_API_URL, weatherData, {
            headers: {
                'Content-Type': 'application/json',
            },
            timeout: 30000,
        });

        return {
            success: true,
            data: response.data,
        };
    } catch (error) {
        console.error('Flood prediction error:', error);
        return {
            success: false,
            error: error.message,
        };
    }
};

/**
 * Mock flood prediction for testing
 */
export const mockPredictFlood = async (currentWeather, historicalWeather) => {
    // Simulate API delay
    await new Promise(resolve => setTimeout(resolve, 2000));

    // Calculate risk based on rainfall
    const currentRain = currentWeather.rain?.['1h'] || 0;
    const yesterdayRain = historicalWeather.current?.rain?.['1h'] || 0;
    const totalRainfall = currentRain + yesterdayRain;

    // Simple mock logic
    const isHighRisk = totalRainfall > 20 || currentWeather.main.humidity > 85;
    const isMediumRisk = totalRainfall > 10 || currentWeather.main.humidity > 70;

    let severity = 'Low';
    let floodRisk = 30;

    if (isHighRisk) {
        severity = 'High';
        floodRisk = 85;
    } else if (isMediumRisk) {
        severity = 'Medium';
        floodRisk = 60;
    }

    return {
        success: true,
        data: {
            isFloodRisk: isHighRisk || isMediumRisk,
            floodProbability: floodRisk,
            severity: severity,
            confidence: (Math.random() * 15 + 85).toFixed(1), // 85-100%
            factors: {
                rainfall: totalRainfall,
                humidity: currentWeather.main.humidity,
                pressure: currentWeather.main.pressure,
                temperature: currentWeather.main.temp,
            },
            recommendations: isHighRisk ? [
                'High flood risk detected in your area',
                'Avoid low-lying areas and flood-prone zones',
                'Prepare emergency supplies and evacuation plan',
                'Monitor local weather alerts closely',
                'Move vehicles to higher ground',
            ] : isMediumRisk ? [
                'Moderate flood risk detected',
                'Stay alert and monitor weather conditions',
                'Avoid unnecessary travel to flood-prone areas',
                'Keep emergency contacts handy',
            ] : [
                'Low flood risk currently',
                'Weather conditions are stable',
                'Continue normal activities',
                'Stay informed about weather updates',
            ],
            weatherSummary: {
                current: {
                    temp: currentWeather.main.temp,
                    humidity: currentWeather.main.humidity,
                    rainfall: currentRain,
                    description: currentWeather.weather[0].description,
                },
                yesterday: {
                    temp: historicalWeather.current?.temp || 0,
                    humidity: historicalWeather.current?.humidity || 0,
                    rainfall: yesterdayRain,
                },
            },
        },
    };
};

/**
 * Get user's current location
 */
export const getCurrentLocation = async () => {
    try {
        // This will be implemented in the component using expo-location
        return {
            success: true,
            coords: {
                latitude: 0,
                longitude: 0,
            },
        };
    } catch (error) {
        return {
            success: false,
            error: error.message,
        };
    }
};
