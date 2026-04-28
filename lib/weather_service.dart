import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  static const apiKey = String.fromEnvironment('OPENWEATHER_API_KEY');

  Future<String> getWeatherRisk({required String city}) async {
    final url =
        'https://api.openweathermap.org/data/2.5/weather?q=$city&appid=$apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      String condition = data['weather'][0]['main'];

      if (condition == 'Rain' || condition == 'Thunderstorm') {
        return 'High';
      } else if (condition == 'Clouds') {
        return 'Medium';
      } else {
        return 'Low';
      }
    } else {
      return 'Low';
    }
  }
}
