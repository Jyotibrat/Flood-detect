"""
Weather Service Module
Handles fetching historical weather data from Open-Meteo API
and IP-based geolocation fallback.
"""

import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional

import requests

logger = logging.getLogger(__name__)

# Open-Meteo API configuration
OPEN_METEO_HISTORICAL_URL = "https://archive-api.open-meteo.com/v1/archive"
OPEN_METEO_FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
IP_GEOLOCATION_URL = "http://ip-api.com/json"


class WeatherService:
    """Service for fetching weather data and geolocation."""

    def __init__(self, request_timeout: int = 30):
        self.timeout = request_timeout
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "FloodPredictionBackend/1.0",
            "Accept": "application/json",
        })

    def get_location_from_ip(
        self, ip_address: Optional[str] = None
    ) -> Dict[str, float]:
        """
        Get latitude and longitude from IP address.

        Args:
            ip_address: Client IP address. If None or localhost,
                        uses external IP detection.

        Returns:
            Dict with 'latitude' and 'longitude' keys.

        Raises:
            RuntimeError: If geolocation lookup fails.
        """
        try:
            url = IP_GEOLOCATION_URL
            # ip-api.com doesn't work with localhost/private IPs,
            # so we let it auto-detect
            if ip_address and ip_address not in (
                "127.0.0.1", "::1", "localhost"
            ):
                url = f"{IP_GEOLOCATION_URL}/{ip_address}"

            response = self.session.get(url, timeout=self.timeout)
            response.raise_for_status()
            data = response.json()

            if data.get("status") == "fail":
                raise RuntimeError(
                    f"IP geolocation failed: {data.get('message')}"
                )

            return {
                "latitude": float(data["lat"]),
                "longitude": float(data["lon"]),
                "city": data.get("city", "Unknown"),
                "country": data.get("country", "Unknown"),
            }

        except requests.RequestException as e:
            logger.error(f"IP geolocation request failed: {e}")
            raise RuntimeError(f"IP geolocation service unavailable: {e}")

    def fetch_historical_weather(
        self,
        latitude: float,
        longitude: float,
        days: int = 10,
    ) -> List[Dict]:
        """
        Fetch historical weather data for the last N days.

        Uses Open-Meteo Archive API for past data.
        Today's data comes from the Forecast API.

        Args:
            latitude: Location latitude.
            longitude: Location longitude.
            days: Number of historical days to fetch (default 10).

        Returns:
            List of daily weather data dictionaries.

        Raises:
            RuntimeError: If weather data cannot be fetched.
        """
        today = datetime.utcnow().date()
        end_date = today - timedelta(days=1)  # Yesterday
        start_date = today - timedelta(days=days)

        logger.info(
            f"Fetching weather data from {start_date} to {end_date} "
            f"for ({latitude}, {longitude})"
        )

        daily_variables = [
            "temperature_2m_max",
            "temperature_2m_min",
            "temperature_2m_mean",
            "precipitation_sum",
            "rain_sum",
            "windspeed_10m_max",
            "et0_fao_evapotranspiration",
        ]

        # Also request hourly humidity data (Open-Meteo archive
        # provides relative_humidity_2m as hourly, not daily)
        hourly_variables = [
            "relative_humidity_2m",
            "soil_moisture_0_to_7cm",
        ]

        weather_records = []

        # ─── Fetch from Archive API ──────────────────────────
        try:
            params = {
                "latitude": latitude,
                "longitude": longitude,
                "start_date": start_date.isoformat(),
                "end_date": end_date.isoformat(),
                "daily": ",".join(daily_variables),
                "hourly": ",".join(hourly_variables),
                "timezone": "UTC",
            }

            response = self.session.get(
                OPEN_METEO_HISTORICAL_URL,
                params=params,
                timeout=self.timeout,
            )
            response.raise_for_status()
            data = response.json()

            weather_records = self._parse_weather_response(data)

        except requests.RequestException as e:
            logger.error(f"Archive API request failed: {e}")
            # Try forecast API as fallback for recent days
            try:
                weather_records = self._fetch_from_forecast_api(
                    latitude, longitude, days
                )
            except Exception as fallback_err:
                logger.error(
                    f"Forecast API fallback also failed: {fallback_err}"
                )
                raise RuntimeError(
                    f"Could not fetch weather data: {e}"
                )

        if not weather_records:
            raise RuntimeError(
                "No weather data returned from API"
            )

        logger.info(
            f"Successfully fetched {len(weather_records)} days "
            f"of weather data"
        )
        return weather_records

    def _fetch_from_forecast_api(
        self,
        latitude: float,
        longitude: float,
        days: int,
    ) -> List[Dict]:
        """
        Fallback: fetch from Open-Meteo Forecast API
        which has past_days parameter.
        """
        params = {
            "latitude": latitude,
            "longitude": longitude,
            "past_days": days,
            "daily": ",".join([
                "temperature_2m_max",
                "temperature_2m_min",
                "precipitation_sum",
                "rain_sum",
                "windspeed_10m_max",
            ]),
            "hourly": "relative_humidity_2m,soil_moisture_0_to_7cm",
            "timezone": "UTC",
            "forecast_days": 0,
        }

        response = self.session.get(
            OPEN_METEO_FORECAST_URL,
            params=params,
            timeout=self.timeout,
        )
        response.raise_for_status()
        data = response.json()
        return self._parse_weather_response(data)

    def _parse_weather_response(self, data: Dict) -> List[Dict]:
        """
        Parse Open-Meteo API response into structured records.

        Args:
            data: Raw JSON response from Open-Meteo.

        Returns:
            List of structured daily weather dictionaries.
        """
        records = []

        daily = data.get("daily", {})
        hourly = data.get("hourly", {})

        dates = daily.get("time", [])
        if not dates:
            return records

        # Pre-compute daily averages for hourly fields
        humidity_daily = self._compute_daily_averages(
            hourly.get("time", []),
            hourly.get("relative_humidity_2m", []),
        )
        soil_moisture_daily = self._compute_daily_averages(
            hourly.get("time", []),
            hourly.get("soil_moisture_0_to_7cm", []),
        )

        for i, date_str in enumerate(dates):
            temp_max = self._safe_get(
                daily, "temperature_2m_max", i
            )
            temp_min = self._safe_get(
                daily, "temperature_2m_min", i
            )
            temp_mean = self._safe_get(
                daily, "temperature_2m_mean", i
            )

            # Compute mean if not available directly
            if temp_mean is None and temp_max is not None and temp_min is not None:
                temp_mean = round((temp_max + temp_min) / 2, 1)

            record = {
                "date": date_str,
                "temperature": {
                    "max": temp_max,
                    "min": temp_min,
                    "mean": temp_mean,
                    "unit": "°C",
                },
                "precipitation": {
                    "total": self._safe_get(
                        daily, "precipitation_sum", i
                    ),
                    "rain": self._safe_get(daily, "rain_sum", i),
                    "unit": "mm",
                },
                "humidity": {
                    "mean": humidity_daily.get(date_str),
                    "unit": "%",
                },
                "wind_speed": {
                    "max": self._safe_get(
                        daily, "windspeed_10m_max", i
                    ),
                    "unit": "km/h",
                },
                "soil_moisture": {
                    "mean": soil_moisture_daily.get(date_str),
                    "unit": "m³/m³",
                },
                "evapotranspiration": {
                    "value": self._safe_get(
                        daily, "et0_fao_evapotranspiration", i
                    ),
                    "unit": "mm",
                },
            }
            records.append(record)

        return records

    @staticmethod
    def _compute_daily_averages(
        hourly_times: List[str],
        hourly_values: List[Optional[float]],
    ) -> Dict[str, Optional[float]]:
        """
        Compute daily averages from hourly data.

        Args:
            hourly_times: List of ISO datetime strings.
            hourly_values: Corresponding hourly values.

        Returns:
            Dict mapping date string to average value.
        """
        if not hourly_times or not hourly_values:
            return {}

        daily_sums: Dict[str, List[float]] = {}

        for time_str, value in zip(hourly_times, hourly_values):
            if value is None:
                continue
            date_key = time_str[:10]  # Extract "YYYY-MM-DD"
            if date_key not in daily_sums:
                daily_sums[date_key] = []
            daily_sums[date_key].append(value)

        return {
            date: round(sum(vals) / len(vals), 2)
            for date, vals in daily_sums.items()
            if vals
        }

    @staticmethod
    def _safe_get(
        data: Dict, key: str, index: int
    ) -> Optional[float]:
        """Safely get a value from a list in a dict."""
        values = data.get(key, [])
        if index < len(values):
            return values[index]
        return None
