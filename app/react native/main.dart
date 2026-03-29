import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(WeatherApp());
}

class WeatherApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WeatherScreen(),
    );
  }
}

class WeatherScreen extends StatefulWidget {
  @override
  _WeatherScreenState createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final String apiKey = "1d64fef393c199842cc38e40d0c80392";

  String city = "";
  double temp = 0;
  String description = "";
  String icon = "";
  int sunrise = 0;
  int sunset = 0;

  List forecast = [];

  LatLng currentPosition = LatLng(23.2599, 77.4126);

  @override
  void initState() {
    super.initState();
    getLocationWeather();
  }

  // 📍 GET LOCATION
  Future<void> getLocationWeather() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    fetchWeather(position.latitude, position.longitude);
  }

  // 🌦 FETCH WEATHER
  Future<void> fetchWeather(double lat, double lon) async {
    currentPosition = LatLng(lat, lon);

    final weatherUrl =
        "https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric";

    final forecastUrl =
        "https://api.openweathermap.org/data/2.5/forecast?lat=$lat&lon=$lon&appid=$apiKey&units=metric";

    final weatherRes = await http.get(Uri.parse(weatherUrl));
    final forecastRes = await http.get(Uri.parse(forecastUrl));

    if (weatherRes.statusCode == 200 && forecastRes.statusCode == 200) {
      final weatherData = jsonDecode(weatherRes.body);
      final forecastData = jsonDecode(forecastRes.body);

      setState(() {
        city = weatherData['name'];
        temp = weatherData['main']['temp'];
        description = weatherData['weather'][0]['description'];
        icon = weatherData['weather'][0]['icon'];
        sunrise = weatherData['sys']['sunrise'];
        sunset = weatherData['sys']['sunset'];
        forecast = forecastData['list'];
      });
    } else {
      print(weatherRes.body);
    }
  }

  String formatTime(int time) {
    return DateFormat('hh:mm a')
        .format(DateTime.fromMillisecondsSinceEpoch(time * 1000));
  }

  String getIconUrl(String iconCode) {
    return "https://openweathermap.org/img/wn/$iconCode@2x.png";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueAccent,
      body: SafeArea(
        child: city.isEmpty
            ? Center(child: CircularProgressIndicator())
            : Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(city,
                  style: TextStyle(
                      fontSize: 28,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),

              SizedBox(height: 10),

              Image.network(getIconUrl(icon), width: 100),

              Text("${temp.toStringAsFixed(1)}°C",
                  style: TextStyle(fontSize: 36, color: Colors.white)),

              Text(description,
                  style:
                  TextStyle(fontSize: 18, color: Colors.white70)),

              SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(children: [
                    Text("Sunrise",
                        style: TextStyle(color: Colors.white)),
                    Text(formatTime(sunrise),
                        style: TextStyle(color: Colors.white)),
                  ]),
                  Column(children: [
                    Text("Sunset",
                        style: TextStyle(color: Colors.white)),
                    Text(formatTime(sunset),
                        style: TextStyle(color: Colors.white)),
                  ]),
                ],
              ),

              SizedBox(height: 20),

              // 🗺 FREE MAP (NO API)
              Container(
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                ),
                clipBehavior: Clip.hardEdge,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: currentPosition,
                    initialZoom: 10,
                    onTap: (tapPosition, point) {
                      fetchWeather(
                          point.latitude, point.longitude);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName:
                      'com.example.weather_app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: currentPosition,
                          width: 40,
                          height: 40,
                          child: Icon(Icons.location_on,
                              color: Colors.red, size: 40),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: 10),

              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: forecast.length ~/ 8,
                  itemBuilder: (context, index) {
                    final item = forecast[index * 8];
                    return Container(
                      margin: EdgeInsets.all(8),
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('E').format(
                                DateTime.fromMillisecondsSinceEpoch(
                                    item['dt'] * 1000)),
                            style: TextStyle(color: Colors.white),
                          ),
                          Image.network(
                              getIconUrl(item['weather'][0]['icon']),
                              width: 50),
                          Text("${item['main']['temp']}°C",
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    );
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
