class RouteRequest {
  const RouteRequest({
    required this.source,
    required this.destination,
    required this.createdAt,
  });

  final String source;
  final String destination;
  final DateTime createdAt;

  String get routeLabel => '$source -> $destination';
}
