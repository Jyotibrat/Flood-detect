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

  TextEditingController searchController = TextEditingController();
  final MapController mapController = MapController();

  bool isLoading = true;
  String errorMessage = "";

  @override
  void initState() {
    super.initState();
    getLocationWeather();
  }

  // 🌙 REAL DAY/NIGHT USING SUNRISE SUNSET
  bool isDayTime() {
    int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= sunrise && now <= sunset;
  }

  Color getTopColor() {
    if (!isDayTime()) return Colors.indigo;

    if (temp <= 15) return Colors.blue;
    if (temp <= 30) return Colors.orange;
    return Colors.redAccent;
  }

  Color getBottomColor() {
    if (!isDayTime()) return Colors.black87;

    if (temp <= 15) return Colors.lightBlue;
    if (temp <= 30) return Colors.deepOrange;
    return Colors.red;
  }

  Widget buildBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [getTopColor(), getBottomColor()],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  // 📍 LOCATION
  Future<void> getLocationWeather() async {
    setState(() => isLoading = true);

    try {
      Position position = await Geolocator.getCurrentPosition()
          .timeout(Duration(seconds: 8));

      fetchWeather(position.latitude, position.longitude);
    } catch (e) {
      fetchWeather(23.2599, 77.4126);
    }
  }

  // 🔍 SEARCH
  Future<void> searchCity(String cityName) async {
    if (cityName.isEmpty) return;

    final res = await http.get(Uri.parse(
        "https://api.openweathermap.org/geo/1.0/direct?q=$cityName&limit=1&appid=$apiKey"));

    final data = jsonDecode(res.body);

    if (data.isNotEmpty) {
      double lat = data[0]['lat'];
      double lon = data[0]['lon'];

      fetchWeather(lat, lon);
      mapController.move(LatLng(lat, lon), 10);
    }
  }

  // 🌦 WEATHER
  Future<void> fetchWeather(double lat, double lon) async {
    setState(() {
      isLoading = true;
      currentPosition = LatLng(lat, lon);
    });

    try {
      final weatherRes = await http.get(Uri.parse(
          "https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric"));

      final forecastRes = await http.get(Uri.parse(
          "https://api.openweathermap.org/data/2.5/forecast?lat=$lat&lon=$lon&appid=$apiKey&units=metric"));

      final weatherData = jsonDecode(weatherRes.body);
      final forecastData = jsonDecode(forecastRes.body);

      List daily = forecastData['list'];
      List filtered = [];

      for (int i = 0; i < daily.length; i += 8) {
        filtered.add(daily[i]);
      }

      setState(() {
        city = weatherData['name'];
        temp = weatherData['main']['temp'];
        description = weatherData['weather'][0]['description'];
        icon = weatherData['weather'][0]['icon'];

        sunrise = weatherData['sys']['sunrise'];
        sunset = weatherData['sys']['sunset'];

        forecast = filtered;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = "Failed to load weather";
        isLoading = false;
      });
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
      body: Stack(
        children: [
          buildBackground(),

          SafeArea(
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: Colors.white))
                : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // 🔍 SEARCH
                  TextField(
                    controller: searchController,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Search city...",
                      hintStyle: TextStyle(color: Colors.white70),
                      prefixIcon: Icon(Icons.search, color: Colors.white),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.send, color: Colors.white),
                        onPressed: () =>
                            searchCity(searchController.text),
                      ),
                    ),
                  ),

                  SizedBox(height: 15),

                  // 🗺 MAP
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: currentPosition,
                        initialZoom: 10,
                        onTap: (tap, point) {
                          fetchWeather(point.latitude, point.longitude);
                          mapController.move(point, 10);
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                          "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                          userAgentPackageName: 'weather_app',
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

                  SizedBox(height: 20),

                  // 🌤 WEATHER CARD (UPDATED WITH SUN/MOON)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment:
                          MainAxisAlignment.center,
                          children: [
                            Text(city,
                                style: TextStyle(
                                    fontSize: 26,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            SizedBox(width: 10),
                            Icon(
                              isDayTime()
                                  ? Icons.wb_sunny
                                  : Icons.nightlight_round,
                              color: isDayTime()
                                  ? Colors.yellow
                                  : Colors.white,
                            )
                          ],
                        ),

                        SizedBox(height: 10),

                        Image.network(getIconUrl(icon), width: 90),

                        Text("${temp.toStringAsFixed(1)}°C",
                            style: TextStyle(
                                fontSize: 42,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),

                        Text(description,
                            style: TextStyle(
                                fontSize: 18,
                                color: Colors.white70)),
                      ],
                    ),
                  ),

                  SizedBox(height: 15),

                  // 🌅 SUNRISE / SUNSET
                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Icon(Icons.wb_sunny,
                              color: Colors.yellow),
                          Text("Sunrise",
                              style:
                              TextStyle(color: Colors.white)),
                          Text(formatTime(sunrise),
                              style:
                              TextStyle(color: Colors.white)),
                        ],
                      ),
                      Column(
                        children: [
                          Icon(Icons.nights_stay,
                              color: Colors.white),
                          Text("Sunset",
                              style:
                              TextStyle(color: Colors.white)),
                          Text(formatTime(sunset),
                              style:
                              TextStyle(color: Colors.white)),
                        ],
                      ),
                    ],
                  ),

                  SizedBox(height: 20),

                  Text("5-Day Forecast",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),

                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: forecast.length,
                      itemBuilder: (context, index) {
                        final item = forecast[index];

                        return Container(
                          width: 100,
                          margin: EdgeInsets.only(right: 12),
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius:
                            BorderRadius.circular(20),
                          ),
                          child: Column(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('E').format(
                                  DateTime
                                      .fromMillisecondsSinceEpoch(
                                      item['dt'] * 1000),
                                ),
                                style:
                                TextStyle(color: Colors.white),
                              ),
                              Image.network(
                                  getIconUrl(item['weather'][0]
                                  ['icon']),
                                  width: 40),
                              Text(
                                "${item['main']['temp']}°C",
                                style:
                                TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.white,
        onPressed: getLocationWeather,
        child: Icon(Icons.my_location, color: Colors.blue),
      ),
    );
  }
}