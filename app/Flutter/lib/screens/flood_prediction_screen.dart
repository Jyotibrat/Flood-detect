import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class FloodPredictionScreen extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String cityName;

  const FloodPredictionScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.cityName,
  });

  @override
  State<FloodPredictionScreen> createState() => _FloodPredictionScreenState();
}

class _FloodPredictionScreenState extends State<FloodPredictionScreen>
    with TickerProviderStateMixin {
  final ApiService _api = ApiService();

  FloodPredictionResponse? _prediction;
  bool _isLoading = true;
  String? _error;

  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _fetchPrediction();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _fetchPrediction() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _api.fetchFloodPrediction(
        latitude: widget.latitude,
        longitude: widget.longitude,
      );
      if (!mounted) return;
      setState(() {
        _prediction = result;
        _isLoading = false;
      });
      _slideController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ─── Color Helpers ────────────────────────────
  Color _riskColor(bool isFlood, double confidence) {
    if (isFlood) {
      if (confidence > 0.7) return const Color(0xFFD32F2F);
      return const Color(0xFFFF6F00);
    }
    if (confidence > 0.7) return const Color(0xFF2E7D32);
    return const Color(0xFF558B2F);
  }

  Color _confidenceColor(double c) {
    if (c >= 0.7) return const Color(0xFF4CAF50);
    if (c >= 0.4) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  List<Color> _backgroundGradient() {
    if (_prediction == null) {
      return [const Color(0xFF1A237E), const Color(0xFF0D47A1)];
    }
    if (_prediction!.isFloodPredicted) {
      return [const Color(0xFFB71C1C), const Color(0xFF880E4F)];
    }
    return [const Color(0xFF0D47A1), const Color(0xFF1B5E20)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _backgroundGradient(),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: _isLoading
                    ? _buildLoadingState()
                    : _error != null
                        ? _buildErrorState()
                        : _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Flood Risk Analysis',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.cityName.isNotEmpty
                      ? widget.cityName
                      : '${widget.latitude.toStringAsFixed(2)}°, ${widget.longitude.toStringAsFixed(2)}°',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _fetchPrediction,
            icon:
                const Icon(Icons.refresh, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  // ─── Loading State ────────────────────────────
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Analyzing flood risk...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fetching 10-day weather data\n& running prediction models',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Error State ──────────────────────────────
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64,
                color: Colors.white.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'Unable to fetch prediction',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure the backend server is running on port 5000',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchPrediction,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Main Body ────────────────────────────────
  Widget _buildBody() {
    final pred = _prediction!;
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _slideController,
        child: RefreshIndicator(
          onRefresh: _fetchPrediction,
          color: Colors.white,
          backgroundColor: Colors.white24,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const SizedBox(height: 8),
              _buildRiskCard(pred),
              const SizedBox(height: 16),
              _buildModelsCard(pred),
              const SizedBox(height: 16),
              _buildGeminiCard(pred),
              const SizedBox(height: 16),
              _buildWeatherHistoryCard(pred),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Risk Hero Card ──────────────────────────
  Widget _buildRiskCard(FloodPredictionResponse pred) {
    final isFlood = pred.isFloodPredicted;
    final conf = pred.overallConfidence;
    final riskCol = _riskColor(isFlood, conf);

    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              riskCol.withOpacity(0.8),
              riskCol.withOpacity(0.5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: riskCol.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              isFlood ? Icons.warning_amber_rounded : Icons.check_circle,
              size: 56,
              color: Colors.white,
            ),
            const SizedBox(height: 12),
            Text(
              pred.gemini.finalPrediction,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Confidence: ${(conf * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Source: ${pred.decisionSource.toUpperCase()}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
            if (pred.status == 'fallback_used') ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'FALLBACK MODE',
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Models Card ─────────────────────────────
  Widget _buildModelsCard(FloodPredictionResponse pred) {
    return _card(
      title: 'Model Predictions',
      icon: Icons.psychology,
      child: Row(
        children: [
          Expanded(
            child: _modelTile(
              'XGBoost',
              pred.models.xgboost,
              const Color(0xFF42A5F5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _modelTile(
              'RL Model',
              pred.models.rl,
              const Color(0xFFAB47BC),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modelTile(String name, SingleModelResult model, Color accent) {
    final available = model.isAvailable;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: available ? accent.withOpacity(0.4) : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          Text(
            name,
            style: TextStyle(
              color: accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (available) ...[
            Icon(
              model.isFlood ? Icons.flood : Icons.shield,
              size: 28,
              color: model.isFlood ? Colors.redAccent : Colors.greenAccent,
            ),
            const SizedBox(height: 6),
            Text(
              model.prediction!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _miniBar('Prob', model.probability ?? 0, accent),
            const SizedBox(height: 4),
            _miniBar('Conf', model.confidence ?? 0, _confidenceColor(model.confidence ?? 0)),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Unavailable',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniBar(String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${(value * 100).toStringAsFixed(0)}%',
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  // ─── Gemini Card ─────────────────────────────
  Widget _buildGeminiCard(FloodPredictionResponse pred) {
    return _card(
      title: 'AI Analysis',
      icon: Icons.auto_awesome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              pred.gemini.analysis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _chipTag(
                'Decision: ${pred.gemini.finalDecisionSource.toUpperCase()}',
                const Color(0xFF7C4DFF),
              ),
              const SizedBox(width: 8),
              _chipTag(
                '${(pred.gemini.confidence * 100).toStringAsFixed(0)}% confident',
                _confidenceColor(pred.gemini.confidence),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ─── Weather History Card ────────────────────
  Widget _buildWeatherHistoryCard(FloodPredictionResponse pred) {
    if (pred.weatherData.isEmpty) {
      return const SizedBox.shrink();
    }

    // Aggregate stats
    double totalPrecip = 0;
    int rainDays = 0;
    double maxPrecipDay = 0;
    double avgHumidity = 0;
    int humidCount = 0;

    for (final d in pred.weatherData) {
      final p = d.precipTotal ?? 0;
      totalPrecip += p;
      if (p > 0.1) rainDays++;
      if (p > maxPrecipDay) maxPrecipDay = p;
      if (d.humidity != null) {
        avgHumidity += d.humidity!;
        humidCount++;
      }
    }
    if (humidCount > 0) avgHumidity /= humidCount;

    return _card(
      title: '10-Day Weather History',
      icon: Icons.history,
      child: Column(
        children: [
          // Stats row
          Row(
            children: [
              _statBox('Total Rain', '${totalPrecip.toStringAsFixed(1)}mm',
                  Icons.water_drop),
              _statBox('Rain Days', '$rainDays/${pred.weatherData.length}',
                  Icons.calendar_today),
              _statBox('Max/Day', '${maxPrecipDay.toStringAsFixed(1)}mm',
                  Icons.arrow_upward),
              _statBox('Avg Humid', '${avgHumidity.toStringAsFixed(0)}%',
                  Icons.opacity),
            ],
          ),
          const SizedBox(height: 14),

          // Daily precipitation chart
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: pred.weatherData.map((day) {
                final p = day.precipTotal ?? 0;
                final maxP = max(maxPrecipDay, 1.0);
                final barHeight = (p / maxP) * 70 + 4;

                return Expanded(
                  child: Tooltip(
                    message:
                        '${day.date}\n${p.toStringAsFixed(1)}mm',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          p > 0.1 ? p.toStringAsFixed(0) : '',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 9,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: barHeight,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                const Color(0xFF42A5F5),
                                p > 30
                                    ? const Color(0xFFE53935)
                                    : p > 10
                                        ? const Color(0xFFFFA726)
                                        : const Color(0xFF66BB6A),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _shortDate(day.date),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Daily Precipitation (mm)',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Icon(icon, size: 16, color: Colors.white38),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('d/M').format(dt);
    } catch (_) {
      return dateStr.length >= 5
          ? dateStr.substring(dateStr.length - 5)
          : dateStr;
    }
  }

  // ─── Shared Card Container ───────────────────
  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
