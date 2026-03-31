import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ╔══════════════════════════════════════════════════════════╗
// ║  CHANGE THIS to the IP of the PC running the backend    ║
// ║  Find it by running 'ipconfig' on that PC               ║
// ╚══════════════════════════════════════════════════════════╝
const String backendHost = '172.25.162.0';
const int backendPort = 5000;

/// Response model for the flood prediction API
class FloodPredictionResponse {
  final LocationData location;
  final List<WeatherDay> weatherData;
  final ModelResults models;
  final GeminiResult gemini;
  final String status;

  FloodPredictionResponse({
    required this.location,
    required this.weatherData,
    required this.models,
    required this.gemini,
    required this.status,
  });

  factory FloodPredictionResponse.fromJson(Map<String, dynamic> json) {
    final loc = json['location'] ?? {};
    final weatherList = json['weather_data'] as List? ?? [];
    final modelsJson = json['models'] ?? {};
    final geminiJson = json['gemini'] ?? {};

    return FloodPredictionResponse(
      location: LocationData(
        lat: (loc['lat'] as num?)?.toDouble() ?? 0,
        lon: (loc['lon'] as num?)?.toDouble() ?? 0,
      ),
      weatherData: weatherList
          .map((w) => WeatherDay.fromJson(w as Map<String, dynamic>))
          .toList(),
      models: ModelResults.fromJson(modelsJson),
      gemini: GeminiResult.fromJson(geminiJson),
      status: json['status'] ?? 'unknown',
    );
  }

  /// Convenience: is there a flood predicted?
  bool get isFloodPredicted =>
      gemini.finalPrediction.toLowerCase() == 'flood';

  /// Overall confidence (from Gemini's final decision)
  double get overallConfidence => gemini.confidence;

  /// Source of the final decision
  String get decisionSource => gemini.finalDecisionSource;
}

class LocationData {
  final double lat;
  final double lon;
  LocationData({required this.lat, required this.lon});
}

class WeatherDay {
  final String date;
  final double? tempMax;
  final double? tempMin;
  final double? tempMean;
  final double? precipTotal;
  final double? humidity;
  final double? windSpeedMax;
  final double? soilMoisture;

  WeatherDay({
    required this.date,
    this.tempMax,
    this.tempMin,
    this.tempMean,
    this.precipTotal,
    this.humidity,
    this.windSpeedMax,
    this.soilMoisture,
  });

  factory WeatherDay.fromJson(Map<String, dynamic> json) {
    final temp = json['temperature'] ?? {};
    final precip = json['precipitation'] ?? {};
    final humid = json['humidity'] ?? {};
    final wind = json['wind_speed'] ?? {};
    final soil = json['soil_moisture'] ?? {};

    return WeatherDay(
      date: json['date'] ?? '',
      tempMax: (temp['max'] as num?)?.toDouble(),
      tempMin: (temp['min'] as num?)?.toDouble(),
      tempMean: (temp['mean'] as num?)?.toDouble(),
      precipTotal: (precip['total'] as num?)?.toDouble(),
      humidity: (humid['mean'] as num?)?.toDouble(),
      windSpeedMax: (wind['max'] as num?)?.toDouble(),
      soilMoisture: (soil['mean'] as num?)?.toDouble(),
    );
  }
}

class ModelResults {
  final SingleModelResult xgboost;
  final SingleModelResult rl;

  ModelResults({required this.xgboost, required this.rl});

  factory ModelResults.fromJson(Map<String, dynamic> json) {
    return ModelResults(
      xgboost: SingleModelResult.fromJson(json['xgboost'] ?? {}),
      rl: SingleModelResult.fromJson(json['rl'] ?? {}),
    );
  }
}

class SingleModelResult {
  final String? prediction;
  final double? probability;
  final double? confidence;

  SingleModelResult({this.prediction, this.probability, this.confidence});

  factory SingleModelResult.fromJson(Map<String, dynamic> json) {
    return SingleModelResult(
      prediction: json['prediction'] as String?,
      probability: (json['probability'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  bool get isFlood => prediction?.toLowerCase() == 'flood';

  bool get isAvailable => prediction != null;
}

class GeminiResult {
  final String analysis;
  final String finalDecisionSource;
  final String finalPrediction;
  final double confidence;

  GeminiResult({
    required this.analysis,
    required this.finalDecisionSource,
    required this.finalPrediction,
    required this.confidence,
  });

  factory GeminiResult.fromJson(Map<String, dynamic> json) {
    return GeminiResult(
      analysis: json['analysis'] ?? 'No analysis available',
      finalDecisionSource: json['final_decision_source'] ?? 'none',
      finalPrediction: json['final_prediction'] ?? 'Unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Service to communicate with the Flask flood prediction backend
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// Override base URL at runtime if needed
  String? _customBaseUrl;
  void setBaseUrl(String url) => _customBaseUrl = url;

  /// Returns the correct backend URL based on platform:
  ///  - Web (Chrome)      → http://localhost:5000
  ///  - Android (emulator or phone) → http://<backendHost>:5000
  ///  - Desktop / iOS     → http://localhost:5000
  String get baseUrl {
    if (_customBaseUrl != null) return _customBaseUrl!;

    // Web runs in the browser on the same machine as backend
    if (kIsWeb) return 'http://localhost:$backendPort';

    // Android (emulator or real phone) → use the backend PC's IP
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://$backendHost:$backendPort';
    }

    // iOS / Desktop
    return 'http://localhost:$backendPort';
  }

  /// Fetch flood prediction for a given location
  Future<FloodPredictionResponse> fetchFloodPrediction({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$baseUrl/predict');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'latitude': latitude,
            'longitude': longitude,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return FloodPredictionResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: error['error'] ?? 'Unknown error',
      );
    }
  }

  /// Health check
  Future<bool> checkHealth() async {
    try {
      final uri = Uri.parse('$baseUrl/health');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
