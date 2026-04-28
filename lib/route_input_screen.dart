import 'package:flutter/material.dart';

import 'route_request.dart';

class RouteInputScreen extends StatefulWidget {
  const RouteInputScreen({super.key});

  @override
  State<RouteInputScreen> createState() => _RouteInputScreenState();
}

class _RouteInputScreenState extends State<RouteInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final sourceController = TextEditingController();
  final destinationController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    sourceController.dispose();
    destinationController.dispose();
    super.dispose();
  }

  Future<void> predictRisk() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final source = sourceController.text.trim();
    final destination = destinationController.text.trim();

    if (source.toLowerCase() == destination.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Source and destination must be different cities.'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final request = RouteRequest(
      source: source,
      destination: destination,
      createdAt: DateTime.now(),
    );

    if (!mounted) {
      return;
    }

    await Navigator.pushNamed(
      context,
      '/dashboard',
      arguments: request,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  void swapCities() {
    final source = sourceController.text;
    sourceController.text = destinationController.text;
    destinationController.text = source;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RouteMind AI'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Plan a route-based delay prediction',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the shipment cities. This route will drive map lookup, weather sampling, and AI prediction.',
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: sourceController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Source City',
                hintText: 'e.g. Mumbai',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.trip_origin),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a source city.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _isSubmitting ? null : swapCities,
                icon: const Icon(Icons.swap_vert),
                label: const Text('Swap'),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: destinationController,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!_isSubmitting) {
                  predictRisk();
                }
              },
              decoration: const InputDecoration(
                labelText: 'Destination City',
                hintText: 'e.g. Bengaluru',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a destination city.';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : predictRisk,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.insights),
                label: Text(
                  _isSubmitting ? 'Route selected' : 'Continue to prediction',
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Next step: fetch route geometry, collect weather signals along that route, and send the structured data to Gemini for the real delay-risk prediction.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
