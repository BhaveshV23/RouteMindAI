import 'dart:convert';

import 'package:http/http.dart' as http;

class GeoCoordinates {
  const GeoCoordinates({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

class GeocodingService {
  GeocodingService({
    String? apiKey,
    http.Client? client,
  })  : apiKey = apiKey ?? const String.fromEnvironment('ORS_API_KEY'),
        _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _geocodeBaseUrl =
      'https://api.openrouteservice.org/geocode/search';

  Future<GeoCoordinates?> getCoordinatesForCity(String cityName) async {
    final trimmedCity = cityName.trim();
    if (trimmedCity.isEmpty || apiKey.isEmpty) {
      return null;
    }

    final uri = Uri.parse(_geocodeBaseUrl).replace(
      queryParameters: {
        'api_key': apiKey,
        'text': trimmedCity,
        'size': '1',
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

      final features = decoded['features'];
      if (features is! List || features.isEmpty) {
        return null;
      }

      final firstFeature = features.first;
      if (firstFeature is! Map<String, dynamic>) {
        return null;
      }

      final geometry = firstFeature['geometry'];
      if (geometry is! Map<String, dynamic>) {
        return null;
      }

      final coordinates = geometry['coordinates'];
      if (coordinates is! List || coordinates.length < 2) {
        return null;
      }

      final longitude = (coordinates[0] as num?)?.toDouble();
      final latitude = (coordinates[1] as num?)?.toDouble();

      if (latitude == null || longitude == null) {
        return null;
      }

      return GeoCoordinates(
        latitude: latitude,
        longitude: longitude,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
