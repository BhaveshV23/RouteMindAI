import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class WeatherSamplingSummary {
  const WeatherSamplingSummary({
    required this.rainDetected,
    required this.averageCloudCoverage,
    required this.stormProbability,
    required this.sampledPointCount,
    required this.totalPointCount,
  });

  final bool rainDetected;
  final double averageCloudCoverage;
  final double stormProbability;
  final int sampledPointCount;
  final int totalPointCount;

  Map<String, dynamic> toJson() {
    return {
      'rainDetected': rainDetected,
      'averageCloudCoverage': averageCloudCoverage,
      'stormProbability': stormProbability,
      'sampledPointCount': sampledPointCount,
      'totalPointCount': totalPointCount,
    };
  }
}

class WeatherSamplingService {
  WeatherSamplingService({
    String? apiKey,
    http.Client? client,
    this.maxSamples = 5,
  })  : apiKey = apiKey ?? const String.fromEnvironment('OPENWEATHER_API_KEY'),
        _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;
  final int maxSamples;

  static const _weatherBaseUrl =
      'https://api.openweathermap.org/data/2.5/weather';

  Future<WeatherSamplingSummary> sampleRouteWeather({
    required List<List<double>> coordinates,
  }) async {
    if (coordinates.isEmpty || apiKey.isEmpty) {
      return WeatherSamplingSummary(
        rainDetected: false,
        averageCloudCoverage: 0,
        stormProbability: 0,
        sampledPointCount: 0,
        totalPointCount: coordinates.length,
      );
    }

    final sampledCoordinates = _selectSamplePoints(coordinates);
    bool rainDetected = false;
    double totalCloudCoverage = 0;
    double totalStormScore = 0;
    int successfulSamples = 0;

    for (final coordinate in sampledCoordinates) {
      final weather = await _fetchWeatherForPoint(coordinate);
      if (weather == null) {
        continue;
      }

      successfulSamples++;
      rainDetected = rainDetected || weather.rainDetected;
      totalCloudCoverage += weather.cloudCoverage;
      totalStormScore += weather.stormScore;
    }

    if (successfulSamples == 0) {
      return WeatherSamplingSummary(
        rainDetected: false,
        averageCloudCoverage: 0,
        stormProbability: 0,
        sampledPointCount: 0,
        totalPointCount: coordinates.length,
      );
    }

    return WeatherSamplingSummary(
      rainDetected: rainDetected,
      averageCloudCoverage: totalCloudCoverage / successfulSamples,
      stormProbability: totalStormScore / successfulSamples,
      sampledPointCount: successfulSamples,
      totalPointCount: coordinates.length,
    );
  }

  List<List<double>> _selectSamplePoints(List<List<double>> coordinates) {
    if (coordinates.length <= maxSamples) {
      return coordinates;
    }

    final sampled = <List<double>>[];
    final lastIndex = coordinates.length - 1;

    for (int i = 0; i < maxSamples; i++) {
      final ratio = maxSamples == 1 ? 0.0 : i / (maxSamples - 1);
      final index = (ratio * lastIndex).round();
      sampled.add(coordinates[index]);
    }

    return sampled;
  }

  Future<_PointWeather?> _fetchWeatherForPoint(List<double> coordinate) async {
    if (coordinate.length < 2) {
      return null;
    }

    final longitude = coordinate[0];
    final latitude = coordinate[1];

    final uri = Uri.parse(_weatherBaseUrl).replace(
      queryParameters: {
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'appid': apiKey,
      },
    );

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final weatherList = decoded['weather'];
      final clouds = decoded['clouds'];

      final descriptions = weatherList is List
          ? weatherList
              .whereType<Map<String, dynamic>>()
              .map((entry) => (entry['main'] ?? '').toString().toLowerCase())
              .toList()
          : <String>[];

      final cloudCoverage = clouds is Map<String, dynamic>
          ? (clouds['all'] as num?)?.toDouble() ?? 0
          : 0.0;

      final rainDetected =
          descriptions.any((item) => item.contains('rain')) ||
          descriptions.any((item) => item.contains('drizzle'));

      final thunderstormDetected =
          descriptions.any((item) => item.contains('thunderstorm'));

      final stormScore = _estimateStormProbability(
        thunderstormDetected: thunderstormDetected,
        rainDetected: rainDetected,
        cloudCoverage: cloudCoverage,
      );

      return _PointWeather(
        rainDetected: rainDetected,
        cloudCoverage: cloudCoverage,
        stormScore: stormScore,
      );
    } catch (_) {
      return null;
    }
  }

  double _estimateStormProbability({
    required bool thunderstormDetected,
    required bool rainDetected,
    required double cloudCoverage,
  }) {
    if (thunderstormDetected) {
      return 1.0;
    }

    if (rainDetected) {
      return min(0.85, 0.35 + (cloudCoverage / 100 * 0.5));
    }

    return min(0.6, cloudCoverage / 100 * 0.4);
  }

  void dispose() {
    _client.close();
  }
}

class _PointWeather {
  const _PointWeather({
    required this.rainDetected,
    required this.cloudCoverage,
    required this.stormScore,
  });

  final bool rainDetected;
  final double cloudCoverage;
  final double stormScore;
}
