import 'dart:convert';

import 'package:http/http.dart' as http;

import 'weather_sampling_service.dart';

class GeminiPredictionResult {
  const GeminiPredictionResult({
    required this.riskLevel,
    required this.delayProbabilityPercentage,
    required this.reasonForDisruption,
    required this.alternateRouteSuggestion,
  });

  final String riskLevel;
  final int delayProbabilityPercentage;
  final String reasonForDisruption;
  final String alternateRouteSuggestion;

  factory GeminiPredictionResult.fromJson(Map<String, dynamic> json) {
    final probability = json['delayProbabilityPercentage'];

    return GeminiPredictionResult(
      riskLevel: (json['riskLevel'] ?? 'Unknown').toString(),
      delayProbabilityPercentage: probability is num
          ? probability.round()
          : int.tryParse(probability?.toString() ?? '') ?? 0,
      reasonForDisruption: (json['reasonForDisruption'] ?? '').toString(),
      alternateRouteSuggestion:
          (json['alternateRouteSuggestion'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'riskLevel': riskLevel,
      'delayProbabilityPercentage': delayProbabilityPercentage,
      'reasonForDisruption': reasonForDisruption,
      'alternateRouteSuggestion': alternateRouteSuggestion,
    };
  }
}

class GeminiPredictionService {
  GeminiPredictionService({
    String? apiKey,
    http.Client? client,
    this.model = 'gemini-2.5-flash',
  })  : apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY'),
        _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  String get _endpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

  Future<GeminiPredictionResult> predictDelayRisk({
    required String sourceCity,
    required String destinationCity,
    required double routeDistanceKm,
    required WeatherSamplingSummary weatherSummary,
  }) async {
    if (apiKey.isEmpty) {
      return _fallbackResult();
    }

    try {
      final response = await _client.post(
        Uri.parse(_endpoint),
        headers: {
          'x-goog-api-key': apiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text': _buildPrompt(
                    sourceCity: sourceCity,
                    destinationCity: destinationCity,
                    routeDistanceKm: routeDistanceKm,
                    weatherSummary: weatherSummary,
                  ),
                },
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseJsonSchema': {
              'type': 'object',
              'properties': {
                'riskLevel': {
                  'type': 'string',
                  'enum': ['Low', 'Medium', 'High'],
                  'description':
                      'Overall route delay risk classification for this shipment.',
                },
                'delayProbabilityPercentage': {
                  'type': 'integer',
                  'minimum': 0,
                  'maximum': 100,
                  'description':
                      'Estimated probability of delay as a percentage from 0 to 100.',
                },
                'reasonForDisruption': {
                  'type': 'string',
                  'description':
                      'Short explanation describing the main disruption factors.',
                },
                'alternateRouteSuggestion': {
                  'type': 'string',
                  'description':
                      'A practical alternate route or fallback routing suggestion.',
                },
              },
              'required': [
                'riskLevel',
                'delayProbabilityPercentage',
                'reasonForDisruption',
                'alternateRouteSuggestion',
              ],
              'propertyOrdering': [
                'riskLevel',
                'delayProbabilityPercentage',
                'reasonForDisruption',
                'alternateRouteSuggestion',
              ],
            },
          },
        }),
      );

      if (response.statusCode != 200) {
        print('GEMINI API ERROR HTTP ${response.statusCode}: ${response.body}');
        return _fallbackResult();
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _fallbackResult();
      }

      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        return _fallbackResult();
      }

      final candidate = candidates.first;
      if (candidate is! Map<String, dynamic>) {
        return _fallbackResult();
      }

      final content = candidate['content'];
      if (content is! Map<String, dynamic>) {
        return _fallbackResult();
      }

      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) {
        return _fallbackResult();
      }

      final firstPart = parts.first;
      if (firstPart is! Map<String, dynamic>) {
        return _fallbackResult();
      }

      final text = firstPart['text'];
      if (text is! String || text.trim().isEmpty) {
        return _fallbackResult();
      }

      final predictionJson = jsonDecode(text);
      if (predictionJson is! Map<String, dynamic>) {
        return _fallbackResult();
      }

      return GeminiPredictionResult.fromJson(predictionJson);
    } catch (error, stackTrace) {
      print('GEMINI EXCEPTION: $error');
      print('STACKTRACE: $stackTrace');
      return _fallbackResult();
    }
  }

  Future<Map<String, dynamic>> predictDelayRiskJson({
    required String sourceCity,
    required String destinationCity,
    required double routeDistanceKm,
    required WeatherSamplingSummary weatherSummary,
  }) async {
    final result = await predictDelayRisk(
      sourceCity: sourceCity,
      destinationCity: destinationCity,
      routeDistanceKm: routeDistanceKm,
      weatherSummary: weatherSummary,
    );

    return result.toJson();
  }

  String _buildPrompt({
    required String sourceCity,
    required String destinationCity,
    required double routeDistanceKm,
    required WeatherSamplingSummary weatherSummary,
  }) {
    return '''
You are a logistics risk prediction assistant for RouteMind AI.

Analyze the route and weather signals below and estimate shipment delay risk.
Return only the structured JSON requested by the schema.

Route details:
- Source city: $sourceCity
- Destination city: $destinationCity
- Route distance (km): ${routeDistanceKm.toStringAsFixed(1)}

Weather summary along route:
- Rain detected: ${weatherSummary.rainDetected}
- Average cloud coverage: ${weatherSummary.averageCloudCoverage.toStringAsFixed(1)}
- Storm probability: ${weatherSummary.stormProbability.toStringAsFixed(2)}
- Sampled route points: ${weatherSummary.sampledPointCount}
- Total route points: ${weatherSummary.totalPointCount}

Prediction rules:
- High risk means severe likely disruption and major delay chance.
- Medium risk means moderate instability and possible delivery slowdown.
- Low risk means generally stable conditions with limited disruption signs.
- Delay probability must be an integer from 0 to 100.
- Reason should be concise and specific to route distance and weather.
- Alternate route suggestion should be practical and short.
''';
  }

  GeminiPredictionResult _fallbackResult() {
    return const GeminiPredictionResult(
      riskLevel: 'Unknown',
      delayProbabilityPercentage: 0,
      reasonForDisruption: 'Prediction unavailable.',
      alternateRouteSuggestion: 'Keep the current route and retry prediction.',
    );
  }

  void dispose() {
    _client.close();
  }
}
