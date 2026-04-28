import 'dart:convert';

import 'package:http/http.dart' as http;

import 'geocoding_service.dart';

class RouteService {
  RouteService({
    String? apiKey,
    http.Client? client,
    GeocodingService? geocodingService,
  })  : apiKey = apiKey ?? const String.fromEnvironment('ORS_API_KEY'),
        _client = client ?? http.Client(),
        _geocodingService = geocodingService ??
            GeocodingService(
              apiKey: apiKey ?? const String.fromEnvironment('ORS_API_KEY'),
            );

  final String apiKey;
  final http.Client _client;
  final GeocodingService _geocodingService;

  static const _directionsBaseUrl =
      'https://api.openrouteservice.org/v2/directions';

  Future<List<List<double>>> fetchRouteCoordinates({
    required String sourceCity,
    required String destinationCity,
    String profile = 'driving-car',
  }) async {
    if (apiKey.isEmpty) {
      return [];
    }

    try {
      final sourceCoordinates =
          await _geocodingService.getCoordinatesForCity(sourceCity);
      final destinationCoordinates =
          await _geocodingService.getCoordinatesForCity(destinationCity);

      if (sourceCoordinates == null || destinationCoordinates == null) {
        return [];
      }

      final uri = Uri.parse('$_directionsBaseUrl/$profile/geojson');
      final response = await _client.post(
        uri,
        headers: {
          'Authorization': apiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'coordinates': [
            [sourceCoordinates.longitude, sourceCoordinates.latitude],
            [destinationCoordinates.longitude, destinationCoordinates.latitude],
          ],
        }),
      );

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return [];
      }

      final features = decoded['features'];
      if (features is! List || features.isEmpty) {
        return [];
      }

      final feature = features.first;
      if (feature is! Map<String, dynamic>) {
        return [];
      }

      final geometry = feature['geometry'];
      if (geometry is! Map<String, dynamic>) {
        return [];
      }

      final coordinates = geometry['coordinates'];
      if (coordinates is! List) {
        return [];
      }

      return coordinates
          .whereType<List>()
          .map((point) {
            if (point.length < 2) {
              return <double>[];
            }

            final longitude = (point[0] as num?)?.toDouble();
            final latitude = (point[1] as num?)?.toDouble();

            if (longitude == null || latitude == null) {
              return <double>[];
            }

            return <double>[longitude, latitude];
          })
          .where((point) => point.length == 2)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _client.close();
    _geocodingService.dispose();
  }
}
