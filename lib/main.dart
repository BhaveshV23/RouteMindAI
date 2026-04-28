import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'firebase_options.dart';
import 'gemini_prediction_service.dart';
import 'route_input_screen.dart';
import 'route_request.dart';
import 'route_service.dart';
import 'weather_sampling_service.dart';

class AppRoutes {
  static const routeInput = '/';
  static const dashboard = '/dashboard';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RouteMind AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      initialRoute: AppRoutes.routeInput,
      routes: {
        AppRoutes.routeInput: (_) => const RouteInputScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.dashboard) {
          final request = settings.arguments;
          RouteRequest? routeRequest;

          if (request is RouteRequest) {
            routeRequest = request;
          } else if (request is Map) {
            final source = request['source']?.toString().trim();
            final destination = request['destination']?.toString().trim();

            if (source != null &&
                source.isNotEmpty &&
                destination != null &&
                destination.isNotEmpty) {
              routeRequest = RouteRequest(
                source: source,
                destination: destination,
                createdAt: DateTime.now(),
              );
            }
          }

          return MaterialPageRoute<void>(
            builder: (_) => HomeScreen(routeRequest: routeRequest),
          );
        }

        return null;
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.routeRequest,
  });

  final RouteRequest? routeRequest;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _routeService = RouteService();
  final _weatherSamplingService = WeatherSamplingService();
  final _geminiPredictionService = GeminiPredictionService();

  int selectedIndex = 0;
  bool _isPredicting = false;
  String? _predictionError;
  late Future<List<List<double>>> _mapRouteCoordinatesFuture;

  RouteRequest? get activeRoute => widget.routeRequest;
  String get activeRouteLabel =>
      activeRoute?.routeLabel ?? 'No route selected yet';

  @override
  void initState() {
    super.initState();
    _mapRouteCoordinatesFuture = _loadMapRouteCoordinates();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeRequest?.routeLabel != widget.routeRequest?.routeLabel) {
      _mapRouteCoordinatesFuture = _loadMapRouteCoordinates();
    }
  }

  @override
  void dispose() {
    _routeService.dispose();
    _weatherSamplingService.dispose();
    _geminiPredictionService.dispose();
    super.dispose();
  }

  Future<List<List<double>>> _loadMapRouteCoordinates() {
    final route = activeRoute;
    if (route == null) {
      return Future.value(<List<double>>[]);
    }

    return _routeService.fetchRouteCoordinates(
      sourceCity: route.source,
      destinationCity: route.destination,
    );
  }

  Color getRiskColor(String risk) {
    switch (risk) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      case 'Low':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> runPrediction() async {
    final route = activeRoute;
    if (route == null) {
      setState(() {
        _predictionError = 'Select a route before running prediction.';
      });
      return;
    }

    setState(() {
      _isPredicting = true;
      _predictionError = null;
    });

    try {
      final routeCoordinates = await _routeService.fetchRouteCoordinates(
        sourceCity: route.source,
        destinationCity: route.destination,
      );

      if (routeCoordinates.isEmpty) {
        throw Exception('No route coordinates were returned.');
      }

      final weatherSummary = await _weatherSamplingService.sampleRouteWeather(
        coordinates: routeCoordinates,
      );

      final routeDistanceKm = _calculateRouteDistanceKm(routeCoordinates);
      final prediction = await _geminiPredictionService.predictDelayRisk(
        sourceCity: route.source,
        destinationCity: route.destination,
        routeDistanceKm: routeDistanceKm,
        weatherSummary: weatherSummary,
      );

      await FirebaseFirestore.instance.collection('route_predictions').add({
        'source': route.source,
        'destination': route.destination,
        'route': activeRouteLabel,
        'riskLevel': prediction.riskLevel,
        'delayProbabilityPercentage': prediction.delayProbabilityPercentage,
        'reasonForDisruption': prediction.reasonForDisruption,
        'alternateRouteSuggestion': prediction.alternateRouteSuggestion,
        'routeDistanceKm': routeDistanceKm,
        'weatherSummary': weatherSummary.toJson(),
        'routeCoordinates': routeCoordinates.map((coord) => {'lon': coord[0], 'lat': coord[1]}).toList(),
        'timestamp': DateTime.now(),
      });

      if (mounted && prediction.riskLevel == 'High') {
        showHighRiskAlert(context);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _predictionError = 'Prediction failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPredicting = false;
        });
      }
    }
  }

  void showHighRiskAlert(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('High Risk Detected'),
          content: const Text(
            'RouteMind AI detected a high delay risk. Consider the suggested alternate route.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  double _calculateRouteDistanceKm(List<List<double>> coordinates) {
    if (coordinates.length < 2) {
      return 0;
    }

    double totalDistanceKm = 0;
    for (int index = 1; index < coordinates.length; index++) {
      final previous = coordinates[index - 1];
      final current = coordinates[index];
      totalDistanceKm += _haversineDistanceKm(
        previous[1],
        previous[0],
        current[1],
        current[0],
      );
    }

    return totalDistanceKm;
  }

  double _haversineDistanceKm(
    double startLat,
    double startLon,
    double endLat,
    double endLon,
  ) {
    const earthRadiusKm = 6371.0;
    final deltaLat = _toRadians(endLat - startLat);
    final deltaLon = _toRadians(endLon - startLon);
    final a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(_toRadians(startLat)) *
            cos(_toRadians(endLat)) *
            sin(deltaLon / 2) *
            sin(deltaLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  String _normalizeReason(String reason) {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      return 'Unspecified';
    }

    final normalized = trimmed.toLowerCase();
    if (normalized.contains('rain')) {
      return 'Rain';
    }
    if (normalized.contains('storm') || normalized.contains('thunder')) {
      return 'Storm';
    }
    if (normalized.contains('cloud')) {
      return 'Cloud cover';
    }
    if (normalized.contains('traffic') || normalized.contains('congestion')) {
      return 'Traffic congestion';
    }
    if (normalized.contains('wind')) {
      return 'Strong wind';
    }

    return trimmed;
  }

  _AnalyticsSummary _buildAnalyticsSummary(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return const _AnalyticsSummary(
        averageDelayProbability: 0,
        mostCommonReason: 'No data',
        highRiskCorridors: [],
      );
    }

    double totalDelayProbability = 0;
    final reasonFrequency = <String, int>{};
    final corridorFrequency = <String, int>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final rawProbability = data['delayProbabilityPercentage'];
      final delayProbability = rawProbability is num
          ? rawProbability.toDouble()
          : double.tryParse(rawProbability?.toString() ?? '') ?? 0;
      totalDelayProbability += delayProbability;

      final reason = _normalizeReason(
        (data['reasonForDisruption'] ?? '').toString(),
      );
      reasonFrequency.update(reason, (count) => count + 1, ifAbsent: () => 1);

      final riskLevel = (data['riskLevel'] ?? '').toString();
      if (riskLevel == 'High') {
        final corridor = (data['route'] ?? 'Unknown route').toString();
        corridorFrequency.update(
          corridor,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final averageDelayProbability = totalDelayProbability / docs.length;
    final sortedReasons = reasonFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedCorridors = corridorFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _AnalyticsSummary(
      averageDelayProbability: averageDelayProbability,
      mostCommonReason:
          sortedReasons.isEmpty ? 'No data' : sortedReasons.first.key,
      highRiskCorridors: sortedCorridors.take(3).toList(),
    );
  }

  Widget buildActiveRouteCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Route',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              activeRouteLabel,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              activeRoute == null
                  ? 'Open the route input screen to start a prediction.'
                  : 'This route will be used for route lookup, weather sampling, Gemini prediction, and Firestore storage.',
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPredictionStatusCard() {
    if (_isPredicting) {
      return const Card(
        margin: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Running route lookup, weather sampling, and Gemini prediction...',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_predictionError == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _predictionError!,
          style: TextStyle(color: Colors.red.shade900),
        ),
      ),
    );
  }

  Widget dashboardScreen() {
    return Stack(
      children: [
        Column(
          children: [
            buildActiveRouteCard(),
            buildPredictionStatusCard(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('route_predictions')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final predictions = snapshot.data!.docs;

                  return ListView.builder(
                    itemCount: predictions.length,
                    itemBuilder: (context, index) {
                      final prediction =
                          predictions[index].data() as Map<String, dynamic>;
                      final riskLevel =
                          (prediction['riskLevel'] ?? 'Unknown').toString();
                      final delayProbability =
                          prediction['delayProbabilityPercentage'] ?? 0;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (prediction['route'] ?? 'Unknown route')
                                    .toString(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Text('Risk Level: '),
                                  Text(
                                    riskLevel,
                                    style: TextStyle(
                                      color: getRiskColor(riskLevel),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Delay Probability: $delayProbability%',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Explanation: ${(prediction['reasonForDisruption'] ?? '').toString()}',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Alternate Route: ${(prediction['alternateRouteSuggestion'] ?? '').toString()}',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton.extended(
            onPressed: _isPredicting ? null : runPrediction,
            icon: const Icon(Icons.insights),
            label: Text(_isPredicting ? 'Predicting...' : 'Predict Risk'),
          ),
        ),
      ],
    );
  }

  Widget mapScreen() {
    return Column(
      children: [
        buildActiveRouteCard(),
        Expanded(
          child: FutureBuilder<List<List<double>>>(
            future: _mapRouteCoordinatesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (snapshot.hasError) {
                return const Center(
                  child: Text('Unable to load route map data'),
                );
              }

              final coordinates = snapshot.data ?? <List<double>>[];

              if (coordinates.isEmpty) {
                return const Center(
                  child: Text('No route coordinates available for this route'),
                );
              }

              final routePoints = coordinates
                  .map((point) => LatLng(point[1], point[0]))
                  .toList();

              return FlutterMap(
                options: MapOptions(
                  initialCenter: routePoints.first,
                  initialZoom: 5,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        strokeWidth: 4,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: routePoints.first,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.trip_origin,
                          color: Colors.green,
                          size: 28,
                        ),
                      ),
                      Marker(
                        point: routePoints.last,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget analyticsScreen() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('route_predictions')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final docs = snapshot.data!.docs;
        final summary = _buildAnalyticsSummary(docs);

        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                buildActiveRouteCard(),
                const SizedBox(height: 24),
                const Expanded(
                  child: Center(
                    child: Text('No route prediction analytics available yet'),
                  ),
                ),
              ],
            ),
          );
        }

        final corridorBars = summary.highRiskCorridors.isEmpty
            ? <BarChartGroupData>[
                BarChartGroupData(
                  x: 0,
                  barRods: [BarChartRodData(toY: 0)],
                ),
              ]
            : List<BarChartGroupData>.generate(
                summary.highRiskCorridors.length,
                (index) {
                  final corridor = summary.highRiskCorridors[index];
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: corridor.value.toDouble(),
                        color: Colors.redAccent,
                        width: 20,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  );
                },
              );

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              buildActiveRouteCard(),
              const SizedBox(height: 16),
              const Text(
                'Route Prediction Analytics',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Average Delay Probability',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${summary.averageDelayProbability.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 24,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Most Common Disruption',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              summary.mostCommonReason,
                              style: const TextStyle(
                                fontSize: 20,
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'High-Risk Corridor Frequency',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: BarChart(
                  BarChartData(
                    maxY: summary.highRiskCorridors.isEmpty
                        ? 1
                        : summary.highRiskCorridors
                                .map((entry) => entry.value)
                                .reduce((a, b) => a > b ? a : b)
                                .toDouble() +
                            1,
                    barGroups: corridorBars,
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: true, reservedSize: 28),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 ||
                                index >= summary.highRiskCorridors.length) {
                              return const SizedBox.shrink();
                            }

                            final label = summary.highRiskCorridors[index].key;
                            final compactLabel = label.length > 16
                                ? '${label.substring(0, 16)}...'
                                : label;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                compactLabel,
                                style: const TextStyle(fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: true),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      dashboardScreen(),
      mapScreen(),
      analyticsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('RouteMind AI Control Center'),
      ),
      body: screens[selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }
}

class _AnalyticsSummary {
  const _AnalyticsSummary({
    required this.averageDelayProbability,
    required this.mostCommonReason,
    required this.highRiskCorridors,
  });

  final double averageDelayProbability;
  final String mostCommonReason;
  final List<MapEntry<String, int>> highRiskCorridors;
}
