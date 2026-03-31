"""
Gemini AI Service Module
Handles Google Gemini API integration for flood prediction analysis,
validation, and independent prediction as a failsafe.
"""

import json
import logging
import re
from typing import Dict, List, Optional

import requests

logger = logging.getLogger(__name__)

GEMINI_API_URL = (
    "https://generativelanguage.googleapis.com/v1beta/"
    "models/gemini-2.0-flash:generateContent"
)


class GeminiService:
    """
    Service for Gemini AI-powered flood prediction analysis.

    Responsibilities:
    1. Analyze weather data and model outputs
    2. Validate model predictions with reasoning
    3. Override predictions if deemed unreliable
    4. Generate independent predictions as failsafe
    """

    def __init__(self, api_key: str = ""):
        self.api_key = api_key
        self.session = requests.Session()
        self.session.headers.update({
            "Content-Type": "application/json",
        })

    def is_configured(self) -> bool:
        """Check if Gemini API key is configured."""
        return bool(self.api_key and len(self.api_key) > 10)

    def analyze_and_decide(
        self,
        weather_data: List[Dict],
        xgboost_result: Optional[Dict],
        rl_result: Optional[Dict],
        latitude: float,
        longitude: float,
        models_failed: bool = False,
    ) -> Dict:
        """
        Analyze weather data and model outputs using Gemini AI.

        Decision logic:
        1. If models succeeded → validate predictions, return best
        2. If models partially failed → validate surviving model
        3. If both models failed → generate independent prediction

        Args:
            weather_data: Historical weather data (last 10 days).
            xgboost_result: XGBoost model output or None.
            rl_result: RL model output or None.
            latitude: Location latitude.
            longitude: Location longitude.
            models_failed: Whether both models failed entirely.

        Returns:
            Dict with analysis, final_decision_source,
            final_prediction, and confidence.
        """
        if not self.is_configured():
            logger.warning("Gemini API key not configured")
            return self._fallback_analysis(
                xgboost_result, rl_result, models_failed
            )

        try:
            if models_failed:
                return self._independent_prediction(
                    weather_data, latitude, longitude
                )
            else:
                return self._validate_and_decide(
                    weather_data,
                    xgboost_result,
                    rl_result,
                    latitude,
                    longitude,
                )
        except Exception as e:
            logger.error(f"Gemini analysis failed: {e}")
            return self._fallback_analysis(
                xgboost_result, rl_result, models_failed
            )

    def _validate_and_decide(
        self,
        weather_data: List[Dict],
        xgboost_result: Optional[Dict],
        rl_result: Optional[Dict],
        latitude: float,
        longitude: float,
    ) -> Dict:
        """
        Use Gemini to validate model predictions and decide
        the final output.
        """
        prompt = self._build_validation_prompt(
            weather_data, xgboost_result, rl_result,
            latitude, longitude
        )

        response = self._call_gemini(prompt)

        if response is None:
            return self._fallback_analysis(
                xgboost_result, rl_result, False
            )

        return self._parse_gemini_response(
            response, xgboost_result, rl_result
        )

    def _independent_prediction(
        self,
        weather_data: List[Dict],
        latitude: float,
        longitude: float,
    ) -> Dict:
        """
        Generate a fully independent Gemini prediction
        when both models have failed.
        """
        prompt = self._build_independent_prompt(
            weather_data, latitude, longitude
        )

        response = self._call_gemini(prompt)

        if response is None:
            return {
                "analysis": (
                    "Both ML models failed and Gemini analysis "
                    "is unavailable. Cannot provide prediction."
                ),
                "final_decision_source": "none",
                "final_prediction": "Unknown",
                "confidence": 0.0,
            }

        return self._parse_independent_response(response)

    def _build_validation_prompt(
        self,
        weather_data: List[Dict],
        xgboost_result: Optional[Dict],
        rl_result: Optional[Dict],
        latitude: float,
        longitude: float,
    ) -> str:
        """Build the prompt for model validation."""

        weather_summary = self._summarize_weather(weather_data)

        prompt = f"""You are an expert hydrologist and flood prediction analyst.

TASK: Analyze the following weather data and ML model predictions for flood risk at coordinates ({latitude}, {longitude}).

=== WEATHER DATA (Last 10 Days) ===
{weather_summary}

=== MODEL PREDICTIONS ===
XGBoost Model: {json.dumps(xgboost_result) if xgboost_result else "FAILED / Unavailable"}
RL Model: {json.dumps(rl_result) if rl_result else "FAILED / Unavailable"}

=== YOUR ANALYSIS TASKS ===
1. Analyze the weather patterns for flood indicators:
   - Sustained heavy rainfall
   - Rapidly increasing precipitation trends
   - High soil moisture saturation
   - High humidity combined with rainfall
   
2. Evaluate each model's prediction:
   - Is the XGBoost prediction reasonable given the weather data?
   - Is the RL prediction reasonable given the weather data?
   - Are they consistent with each other?

3. Consider external factors:
   - Seasonal flood patterns for this location
   - Geographic flood susceptibility
   - Cumulative precipitation effects

4. Make your final decision:
   - If a model prediction is reliable, select it
   - If predictions conflict, choose the more credible one
   - If both seem wrong, provide your own prediction

RESPOND IN THIS EXACT JSON FORMAT:
{{
    "analysis": "<detailed analysis string (2-3 sentences)>",
    "xgboost_reliable": <true/false>,
    "rl_reliable": <true/false>,
    "final_decision_source": "<xgboost | rl | gemini>",
    "final_prediction": "<Flood | No Flood>",
    "confidence": <0.0 to 1.0>,
    "reasoning": "<brief reasoning for decision>"
}}

ONLY output valid JSON. No markdown, no extra text."""

        return prompt

    def _build_independent_prompt(
        self,
        weather_data: List[Dict],
        latitude: float,
        longitude: float,
    ) -> str:
        """Build prompt for independent prediction (models failed)."""

        weather_summary = self._summarize_weather(weather_data)

        prompt = f"""You are an expert hydrologist and flood prediction analyst.

CRITICAL: Both ML prediction models have FAILED. You must provide an independent flood risk assessment.

TASK: Analyze weather data and predict flood risk at coordinates ({latitude}, {longitude}).

=== WEATHER DATA (Last 10 Days) ===
{weather_summary}

=== FLOOD RISK INDICATORS TO EVALUATE ===
1. Total and average precipitation over the period
2. Maximum single-day rainfall (>50mm is concerning)
3. Precipitation trend (increasing is worse)
4. Number of consecutive rain days
5. Average humidity levels (>80% increases risk)
6. Soil moisture levels (higher = less absorption capacity)
7. Wind speed patterns (storms)
8. Temperature patterns (snowmelt risk)

=== ASSESSMENT CRITERIA ===
- LOW RISK: <20mm total precip, no sustained rain, low humidity
- MODERATE RISK: 20-50mm total, some rain days, moderate humidity
- HIGH RISK: 50-100mm total, sustained rain, high humidity/soil moisture
- CRITICAL RISK: >100mm total, increasing trend, saturated soil

RESPOND IN THIS EXACT JSON FORMAT:
{{
    "analysis": "<detailed analysis string (2-3 sentences)>",
    "final_decision_source": "gemini",
    "final_prediction": "<Flood | No Flood>",
    "confidence": <0.0 to 1.0>,
    "reasoning": "<brief reasoning>"
}}

ONLY output valid JSON. No markdown, no extra text."""

        return prompt

    def _summarize_weather(self, weather_data: List[Dict]) -> str:
        """Create a concise weather summary for the prompt."""
        if not weather_data:
            return "No weather data available."

        lines = []
        total_precip = 0
        rain_days = 0

        for day in weather_data:
            date = day.get("date", "Unknown")
            temp = day.get("temperature", {})
            precip = day.get("precipitation", {})
            humid = day.get("humidity", {})
            wind = day.get("wind_speed", {})
            soil = day.get("soil_moisture", {})

            precip_total = precip.get("total") or 0
            total_precip += precip_total
            if precip_total > 0.1:
                rain_days += 1

            lines.append(
                f"  {date}: "
                f"Temp {temp.get('min', '?')}–{temp.get('max', '?')}°C "
                f"(mean {temp.get('mean', '?')}°C), "
                f"Precip {precip_total}mm, "
                f"Humidity {humid.get('mean', '?')}%, "
                f"Wind {wind.get('max', '?')}km/h, "
                f"Soil moisture {soil.get('mean', '?')}m³/m³"
            )

        summary = "\n".join(lines)
        summary += (
            f"\n\n  TOTALS: {total_precip:.1f}mm total precipitation, "
            f"{rain_days} rain days out of {len(weather_data)}"
        )
        return summary

    def _call_gemini(self, prompt: str) -> Optional[str]:
        """
        Make API call to Gemini.

        Args:
            prompt: The text prompt to send.

        Returns:
            Response text or None on failure.
        """
        url = f"{GEMINI_API_URL}?key={self.api_key}"

        payload = {
            "contents": [
                {
                    "parts": [
                        {"text": prompt}
                    ]
                }
            ],
            "generationConfig": {
                "temperature": 0.2,
                "topP": 0.8,
                "maxOutputTokens": 1024,
            },
        }

        try:
            response = self.session.post(
                url,
                json=payload,
                timeout=30,
            )

            if response.status_code == 401:
                logger.error("Gemini API: Invalid API key")
                return None
            elif response.status_code == 429:
                logger.error("Gemini API: Rate limited")
                return None
            elif response.status_code != 200:
                logger.error(
                    f"Gemini API error {response.status_code}: "
                    f"{response.text[:500]}"
                )
                return None

            data = response.json()

            # Extract text from response
            candidates = data.get("candidates", [])
            if not candidates:
                logger.error("Gemini returned no candidates")
                return None

            content = candidates[0].get("content", {})
            parts = content.get("parts", [])
            if not parts:
                logger.error("Gemini returned no content parts")
                return None

            text = parts[0].get("text", "")
            logger.info(f"Gemini response length: {len(text)} chars")
            return text

        except requests.RequestException as e:
            logger.error(f"Gemini API request failed: {e}")
            return None
        except (KeyError, IndexError, json.JSONDecodeError) as e:
            logger.error(f"Gemini response parsing error: {e}")
            return None

    def _parse_gemini_response(
        self,
        response_text: str,
        xgboost_result: Optional[Dict],
        rl_result: Optional[Dict],
    ) -> Dict:
        """Parse Gemini's validation response."""
        try:
            # Try to extract JSON from response
            json_data = self._extract_json(response_text)

            if json_data is None:
                logger.warning(
                    "Could not parse Gemini response as JSON"
                )
                return self._fallback_analysis(
                    xgboost_result, rl_result, False
                )

            # Validate required fields
            analysis = json_data.get(
                "analysis",
                "Gemini analysis completed."
            )
            source = json_data.get(
                "final_decision_source", "gemini"
            )
            prediction = json_data.get(
                "final_prediction", "Unknown"
            )
            confidence = float(json_data.get("confidence", 0.5))

            # Clamp confidence
            confidence = max(0.0, min(1.0, confidence))

            # Validate source
            if source not in ("xgboost", "rl", "gemini"):
                source = "gemini"

            # Validate prediction
            if prediction not in ("Flood", "No Flood"):
                prediction = (
                    "Flood" if "flood" in prediction.lower()
                    else "No Flood"
                )

            return {
                "analysis": analysis,
                "final_decision_source": source,
                "final_prediction": prediction,
                "confidence": round(confidence, 4),
            }

        except Exception as e:
            logger.error(f"Error parsing Gemini response: {e}")
            return self._fallback_analysis(
                xgboost_result, rl_result, False
            )

    def _parse_independent_response(
        self, response_text: str
    ) -> Dict:
        """Parse Gemini's independent prediction response."""
        try:
            json_data = self._extract_json(response_text)

            if json_data is None:
                return {
                    "analysis": (
                        "Gemini response could not be parsed. "
                        "Both models failed."
                    ),
                    "final_decision_source": "gemini",
                    "final_prediction": "Unknown",
                    "confidence": 0.0,
                }

            return {
                "analysis": json_data.get(
                    "analysis",
                    "Independent Gemini prediction generated."
                ),
                "final_decision_source": "gemini",
                "final_prediction": json_data.get(
                    "final_prediction", "Unknown"
                ),
                "confidence": round(
                    max(0.0, min(1.0,
                        float(json_data.get("confidence", 0.5))
                    )), 4
                ),
            }

        except Exception as e:
            logger.error(
                f"Error parsing independent Gemini response: {e}"
            )
            return {
                "analysis": "Gemini analysis failed.",
                "final_decision_source": "none",
                "final_prediction": "Unknown",
                "confidence": 0.0,
            }

    @staticmethod
    def _extract_json(text: str) -> Optional[Dict]:
        """
        Extract JSON object from text that may contain
        markdown formatting or extra text.
        """
        # Try direct parse first
        try:
            return json.loads(text.strip())
        except json.JSONDecodeError:
            pass

        # Try to find JSON in markdown code blocks
        patterns = [
            r"```json\s*\n?(.*?)\n?```",
            r"```\s*\n?(.*?)\n?```",
            r"\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}",
        ]

        for pattern in patterns:
            matches = re.findall(pattern, text, re.DOTALL)
            for match in matches:
                try:
                    return json.loads(match.strip())
                except json.JSONDecodeError:
                    continue

        return None

    @staticmethod
    def _fallback_analysis(
        xgboost_result: Optional[Dict],
        rl_result: Optional[Dict],
        models_failed: bool,
    ) -> Dict:
        """
        Generate a fallback analysis without Gemini.
        Uses simple logic to pick the best available prediction.
        """
        if models_failed or (
            xgboost_result is None and rl_result is None
        ):
            return {
                "analysis": (
                    "All prediction systems are unavailable. "
                    "Cannot provide a reliable flood prediction."
                ),
                "final_decision_source": "none",
                "final_prediction": "Unknown",
                "confidence": 0.0,
            }

        # Both available: pick higher confidence
        if xgboost_result and rl_result:
            xg_conf = xgboost_result.get("confidence", 0)
            rl_conf = rl_result.get("confidence", 0)

            # Check agreement
            if (xgboost_result.get("prediction") ==
                    rl_result.get("prediction")):
                # Models agree → high confidence
                source = (
                    "xgboost" if xg_conf >= rl_conf else "rl"
                )
                best = (
                    xgboost_result if xg_conf >= rl_conf
                    else rl_result
                )
                return {
                    "analysis": (
                        f"Both models agree on "
                        f"{best['prediction']}. "
                        f"Using {source} (higher confidence). "
                        f"Gemini validation unavailable."
                    ),
                    "final_decision_source": source,
                    "final_prediction": best.get(
                        "prediction", "Unknown"
                    ),
                    "confidence": round(
                        max(xg_conf, rl_conf), 4
                    ),
                }
            else:
                # Models disagree → pick higher confidence
                if xg_conf >= rl_conf:
                    source, best = "xgboost", xgboost_result
                else:
                    source, best = "rl", rl_result

                return {
                    "analysis": (
                        f"Models disagree. XGBoost predicts "
                        f"{xgboost_result['prediction']} "
                        f"(conf: {xg_conf:.2f}), RL predicts "
                        f"{rl_result['prediction']} "
                        f"(conf: {rl_conf:.2f}). "
                        f"Using {source} with higher confidence. "
                        f"Gemini validation unavailable."
                    ),
                    "final_decision_source": source,
                    "final_prediction": best.get(
                        "prediction", "Unknown"
                    ),
                    "confidence": round(
                        max(xg_conf, rl_conf) * 0.8, 4
                    ),
                }

        # Only one model available
        if xgboost_result:
            return {
                "analysis": (
                    "Only XGBoost model available. "
                    "RL model failed. Gemini unavailable."
                ),
                "final_decision_source": "xgboost",
                "final_prediction": xgboost_result.get(
                    "prediction", "Unknown"
                ),
                "confidence": round(
                    xgboost_result.get("confidence", 0) * 0.8, 4
                ),
            }

        return {
            "analysis": (
                "Only RL model available. "
                "XGBoost model failed. Gemini unavailable."
            ),
            "final_decision_source": "rl",
            "final_prediction": rl_result.get(
                "prediction", "Unknown"
            ),
            "confidence": round(
                rl_result.get("confidence", 0) * 0.8, 4
            ),
        }
