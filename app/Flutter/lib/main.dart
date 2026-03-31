import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/flood_prediction_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://cehvhfpdnlnebmykbbtl.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNlaHZoZnBkbmxuZWJteWtiYnRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4ODgyMzIsImV4cCI6MjA5MDQ2NDIzMn0.4x4HN4nkkxvk--oZ520PGKTpdagcEZ-ITR1VPftOfS8',
  );

  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Weather App',
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    return session == null ? const LoginScreen() : const WeatherScreen();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Enter email and password');
      return;
    }

    setState(() => isLoading = true);

    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      if (res.session != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WeatherScreen()),
        );
      } else {
        _showSnack('Login failed');
      }
    } catch (e) {
      _showSnack('Login failed: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> signup() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Enter email and password');
      return;
    }

    setState(() => isLoading = true);

    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );
      _showSnack('Signup successful. Now login.');
    } catch (e) {
      _showSnack('Signup failed: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueAccent,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Weather App Login',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Email',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Password',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              if (isLoading)
                const CircularProgressIndicator(color: Colors.white)
              else
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: login,
                      child: const Text('Login'),
                    ),
                    TextButton(
                      onPressed: signup,
                      child: const Text(
                        'Create Account',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final String apiKey = '1d64fef393c199842cc38e40d0c80392';

  final TextEditingController searchController = TextEditingController();
  final TextEditingController feedbackController = TextEditingController();
  final MapController mapController = MapController();
  final AudioPlayer audioPlayer = AudioPlayer();

  String city = '';
  double temp = 0;
  String description = '';
  String icon = '';
  int sunrise = 0;
  int sunset = 0;

  List forecast = [];

  LatLng currentPosition = const LatLng(23.2599, 77.4126);

  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    getLocationWeather();
  }

  @override
  void dispose() {
    searchController.dispose();
    feedbackController.dispose();
    audioPlayer.dispose();
    super.dispose();
  }

  bool isDayTime() {
    if (sunrise == 0 || sunset == 0) return true;
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
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

  Future<void> playAlarm() async {
    await audioPlayer.play(AssetSource('alarm.mp3'));
  }

  Future<void> sendFeedback(String message) async {
    final text = message.trim();
    if (text.isEmpty) return;

    try {
      await Supabase.instance.client.from('feedback').insert({
        'message': text,
        'created_at': DateTime.now().toIso8601String(),
        'city': city,
        'temperature': temp,
        'description': description,
      });

      if (!mounted) return;
      feedbackController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback submitted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Feedback failed: $e')),
      );
    }
  }

  Future<void> checkAlert() async {
    try {
      final data = await Supabase.instance.client
          .from('alerts')
          .select()
          .eq('is_danger', true);

      if (data.isNotEmpty) {
        await playAlarm();
      }
    } catch (_) {}
  }

  Future<void> getLocationWeather() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        setState(() {
          isLoading = false;
          errorMessage = 'Location service is disabled';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          isLoading = false;
          errorMessage = 'Location permission denied';
        });
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));

      await fetchWeather(position.latitude, position.longitude);
    } catch (_) {
      await fetchWeather(23.2599, 77.4126);
    }
  }

  Future<void> searchCity(String cityName) async {
    final query = cityName.trim();
    if (query.isEmpty) return;

    try {
      final res = await http.get(Uri.parse(
        'https://api.openweathermap.org/geo/1.0/direct?q=$query&limit=1&appid=$apiKey',
      ));

      if (res.statusCode != 200) {
        throw Exception('City search failed');
      }

      final data = jsonDecode(res.body);

      if (data is List && data.isNotEmpty) {
        final double lat = (data[0]['lat'] as num).toDouble();
        final double lon = (data[0]['lon'] as num).toDouble();

        await fetchWeather(lat, lon);
        mapController.move(LatLng(lat, lon), 10);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('City not found')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    }
  }

  Future<void> fetchWeather(double lat, double lon) async {
    setState(() {
      isLoading = true;
      errorMessage = '';
      currentPosition = LatLng(lat, lon);
    });

    try {
      final weatherRes = await http.get(Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric',
      ));

      final forecastRes = await http.get(Uri.parse(
        'https://api.openweathermap.org/data/2.5/forecast?lat=$lat&lon=$lon&appid=$apiKey&units=metric',
      ));

      if (weatherRes.statusCode != 200 || forecastRes.statusCode != 200) {
        throw Exception('Weather API error');
      }

      final weatherData = jsonDecode(weatherRes.body);
      final forecastData = jsonDecode(forecastRes.body);

      final List daily = forecastData['list'] as List;
      final List filtered = [];

      for (int i = 0; i < daily.length; i += 8) {
        filtered.add(daily[i]);
      }

      setState(() {
        city = weatherData['name'] ?? '';
        temp = (weatherData['main']['temp'] as num).toDouble();
        description = weatherData['weather'][0]['description'] ?? '';
        icon = weatherData['weather'][0]['icon'] ?? '';
        sunrise = weatherData['sys']['sunrise'] ?? 0;
        sunset = weatherData['sys']['sunset'] ?? 0;
        forecast = filtered;
        isLoading = false;
      });

      await checkAlert();
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load weather';
        isLoading = false;
      });
    }
  }

  String formatTime(int time) {
    return DateFormat('hh:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(time * 1000),
    );
  }

  String getIconUrl(String iconCode) {
    return 'https://openweathermap.org/img/wn/$iconCode@2x.png';
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          buildBackground(),
          SafeArea(
            child: isLoading
                ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
                : errorMessage.isNotEmpty
                ? Center(
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.white),
              ),
            )
                : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Search city...",
                      hintStyle:
                      const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.send,
                          color: Colors.white,
                        ),
                        onPressed: () =>
                            searchCity(searchController.text),
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white38),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),

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
                        onTap: (tap, point) async {
                          await fetchWeather(
                            point.latitude,
                            point.longitude,
                          );
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
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
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
                            Flexible(
                              child: Text(
                                city,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 26,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              isDayTime()
                                  ? Icons.wb_sunny
                                  : Icons.nightlight_round,
                              color: isDayTime()
                                  ? Colors.yellow
                                  : Colors.white,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Image.network(getIconUrl(icon), width: 90),
                        Text(
                          "${temp.toStringAsFixed(1)}°C",
                          style: const TextStyle(
                            fontSize: 42,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 15),

                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Icon(
                            Icons.wb_sunny,
                            color: Colors.yellow,
                          ),
                          const Text(
                            "Sunrise",
                            style: TextStyle(color: Colors.white),
                          ),
                          Text(
                            formatTime(sunrise),
                            style:
                            const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(
                            Icons.nights_stay,
                            color: Colors.white,
                          ),
                          const Text(
                            "Sunset",
                            style: TextStyle(color: Colors.white),
                          ),
                          Text(
                            formatTime(sunset),
                            style:
                            const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    "5-Day Forecast",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  SizedBox(
                    height: 130,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: forecast.length,
                      itemBuilder: (context, index) {
                        final item = forecast[index];

                        return Container(
                          width: 100,
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.all(12),
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
                                  DateTime.fromMillisecondsSinceEpoch(
                                    item['dt'] * 1000,
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                              Image.network(
                                getIconUrl(item['weather'][0]['icon']),
                                width: 40,
                              ),
                              Text(
                                "${item['main']['temp']}°C",
                                style: const TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: feedbackController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "Give feedback",
                            hintStyle: const TextStyle(
                              color: Colors.white70,
                            ),
                            filled: true,
                            fillColor: Colors.white24,
                            border: OutlineInputBorder(
                              borderRadius:
                              BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            sendFeedback(feedbackController.text),
                        icon: const Icon(
                          Icons.send,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'flood',
            backgroundColor: const Color(0xFF1565C0),
            icon: const Icon(Icons.flood, color: Colors.white),
            label: const Text(
              'Flood Risk',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FloodPredictionScreen(
                    latitude: currentPosition.latitude,
                    longitude: currentPosition.longitude,
                    cityName: city,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'location',
            backgroundColor: Colors.white,
            onPressed: getLocationWeather,
            child: const Icon(Icons.my_location, color: Colors.blue),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'logout',
            backgroundColor: Colors.red,
            onPressed: logout,
            child: const Icon(Icons.logout),
          ),
        ],
      ),
    );
  }
}