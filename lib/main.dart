import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BikeFitApp());
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0; 
  int _avgHeartRate = 0;
  int _totalHRSum = 0;
  int _hrCount = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  Timer? _watchTimer;
  bool _isWorkingOut = false;
  String _watchModel = ""; 
  bool _isWatchConnected = false; 
  List<FlSpot> _hrSpots = [const FlSpot(0, 0)]; 
  double _timerCounter = 0;

  void _vibrate() => HapticFeedback.lightImpact();

  Future<void> _handleWatchConnection() async {
    _vibrate();
    if (await Permission.bluetoothConnect.request().isGranted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
      );

      await Future.delayed(const Duration(seconds: 2)); 
      Navigator.pop(context);

      setState(() {
        _isWatchConnected = true;
        _watchModel = "Galaxy Watch 6"; 
        _heartRate = 72;
      });
      _startHeartRateMonitoring();
    }
  }

  void _startHeartRateMonitoring() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted || !_isWatchConnected) return;
      setState(() {
        if (_isWorkingOut) {
          _heartRate = 110 + Random().nextInt(50); 
          _totalHRSum += _heartRate;
          _hrCount++;
          _avgHeartRate = _totalHRSum ~/ _hrCount;

          _timerCounter += 0.5;
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 40) _hrSpots.removeAt(0);
          _calories += 0.07;
        } else {
          _heartRate = 60 + Random().nextInt(10); 
        }
      });
    });
  }

  void _toggleWorkout() {
    _vibrate();
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _totalHRSum = 0; _hrCount = 0;
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _duration += const Duration(seconds: 1));
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 배경 이미지 (assets 폴더에 background.png가 있어야 함)
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: Image.asset('assets/background.png', fit: BoxFit.cover,
                errorBuilder: (_,__,___) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.redAccent, Colors.black],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    )
                  )
                )),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                
                const SizedBox(height: 15),

                // 워치 연결 상태 영역
                Center(
                  child: InkWell(
                    onTap: _isWatchConnected ? null : _handleWatchConnection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54, 
                        borderRadius: BorderRadius.circular(20), 
                        border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white24)
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.watch, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white38),
                        const SizedBox(width: 8),
                        Text(_isWatchConnected ? "연결됨: $_watchModel" : "워치 연결하기", style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // [그래프 영역]
                Container(
                  height: 160,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: LineChart(
                    LineChartData(
                      minY: 40, maxY: 180,
                      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.white10, strokeWidth: 1)),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _hrSpots,
                          isCurved: true, barWidth: 3.5, color: Colors.redAccent,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: Colors.redAccent.withOpacity(0.15)),
                        )
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // [데이터 배너] 하단 배치 + 그라데이션 + 가시성 강화
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    padding: const EdgeInsets.symmetric(vertical: 25),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.12), // 상단 광원 효과
                          Colors.black.withOpacity(0.65), // 하단 짙은 배경
                        ],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, spreadRadius: 2)
                      ]
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _boldTile(Icons.favorite, "실시간 심박", _isWatchConnected ? "$_heartRate" : "--", Colors.cyanAccent)),
                            Expanded(child: _boldTile(Icons.trending_up, "평균 심박", "$_avgHeartRate", Colors.redAccent)),
                          ],
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Expanded(child: _boldTile(Icons.local_fire_department, "소모 칼로리", "${_calories.toStringAsFixed(1)}", Colors.orangeAccent)),
                            Expanded(child: _boldTile(Icons.timer, "운동 시간", _formatDuration(_duration), Colors.blueAccent)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 35),

                // 하단 조작 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionBtn("시작/정지", _isWorkingOut ? Icons.pause : Icons.play_arrow, _toggleWorkout),
                      _actionBtn("기록 저장", Icons.save_alt, () {}),
                      _actionBtn("기록 보기", Icons.leaderboard, () {}),
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  // [강조된 데이터 타일 위젯]
  Widget _boldTile(IconData icon, String label, String value, Color color) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: color.withOpacity(0.9)), 
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600)),
        ],
      ),
      const SizedBox(height: 7),
      Text(
        value, 
        style: TextStyle(
          fontSize: 26, 
          fontWeight: FontWeight.w900, 
          color: Colors.white,
          letterSpacing: -0.5,
          shadows: [
            Shadow(color: Colors.black.withOpacity(0.6), blurRadius: 4, offset: const Offset(1, 1))
          ]
        )
      ),
    ],
  );

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap) => Column(
    children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 70, height: 55,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08), 
            borderRadius: BorderRadius.circular(15), 
            border: Border.all(color: Colors.white10)
          ),
          child: Icon(icon, size: 24, color: Colors.white),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)),
    ],
  );

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
