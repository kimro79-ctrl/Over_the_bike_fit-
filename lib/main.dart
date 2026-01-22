import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.delayed(const Duration(seconds: 2));
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
  bool _isWatchConnected = false; 
  List<FlSpot> _hrSpots = [];
  double _timerCounter = 0;
  List<Map<String, dynamic>> _workoutHistory = [];

  void _vibrate() => HapticFeedback.lightImpact();

  Future<void> _handleWatchConnection() async {
    _vibrate();
    if (await Permission.bluetoothConnect.request().isGranted) {
      setState(() { _isWatchConnected = true; _heartRate = 72; });
      _startHeartRateMonitoring();
    }
  }

  void _startHeartRateMonitoring() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted || !_isWatchConnected) return;
      setState(() {
        if (_isWorkingOut) {
          _heartRate = 110 + Random().nextInt(60); 
          // 평균 심박수 계산 로직
          _totalHRSum += _heartRate;
          _hrCount++;
          _avgHeartRate = _totalHRSum ~/ _hrCount;

          _timerCounter += 0.5;
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
          _calories += 0.08;
        } else { 
          _heartRate = 65 + Random().nextInt(10); 
        }
      });
    });
  }

  void _toggleWorkout() {
    _vibrate();
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _totalHRSum = 0; _hrCount = 0; // 시작 시 평균 데이터 초기화
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
          // 배경 이미지
          Positioned.fill(
            child: Opacity(
              opacity: 0.3, 
              child: Image.asset('assets/background.png', fit: BoxFit.cover, 
                errorBuilder: (_,__,___)=>Container(color: Colors.black))
            )
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                const Text('Over The Bike Fit', 
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1.2)),
                
                const SizedBox(height: 15),

                // 워치 연결 버튼
                Center(
                  child: InkWell(
                    onTap: _isWatchConnected ? null : _handleWatchConnection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black54, 
                        borderRadius: BorderRadius.circular(20), 
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.4))
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.watch, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                        const SizedBox(width: 8),
                        Text(_isWatchConnected ? "연결됨" : "워치 대기 중 ❤️", style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ),
                ),

                const SizedBox(height: 45), // 상단 여백 (배너 위치 조절)

                // [데이터 배너] - AVG 포함 및 정중앙 정렬
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.82,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.redAccent.withOpacity(0.1), blurRadius: 20, spreadRadius: 1)
                      ]
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1행: 실시간 심박 & 평균 심박 (AVG)
                        Row(
                          children: [
                            Expanded(child: _miniTile(Icons.favorite, "실시간 심박", _isWatchConnected ? "$_heartRate" : "--", Colors.cyanAccent)),
                            Expanded(child: _miniTile(Icons.trending_up, "평균 심박", "$_avgHeartRate", Colors.redAccent)),
                          ],
                        ),
                        const SizedBox(height: 30), // 행간 간격
                        // 2행: 칼로리 & 운동 시간
                        Row(
                          children: [
                            Expanded(child: _miniTile(Icons.local_fire_department, "소모 칼로리", "${_calories.toStringAsFixed(1)}", Colors.orangeAccent)),
                            Expanded(child: _miniTile(Icons.timer, "운동 시간", _formatDuration(_duration), Colors.blueAccent)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(), // 배너와 그래프 사이 공간 확보

                // 하단 실시간 그래프
                Container(
                  height: 130,
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: LineChart(LineChartData(
                    minY: 40, maxY: 190,
                    gridData: FlGridData(show: false),
                    titlesData: FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _hrSpots.isEmpty ? [const FlSpot(0, 70)] : _hrSpots,
                        isCurved: true, barWidth: 3.5, color: Colors.redAccent, 
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: Colors.redAccent.withOpacity(0.1)),
                      )
                    ],
                  )),
                ),

                const SizedBox(height: 35),

                // 조작 버튼 영역
                Padding(
                  padding: const EdgeInsets.only(bottom: 35),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionBtn("시작/정지", _isWorkingOut ? Icons.pause : Icons.play_arrow, _toggleWorkout),
                      _actionBtn("기록 저장", Icons.save_alt, () {}), // 저장 기능 연결 가능
                      _actionBtn("기록 보기", Icons.leaderboard, () {}), // 리포트 기능 연결 가능
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

  // 데이터 유닛 (AVG 포함 모든 텍스트 정중앙 정렬)
  Widget _miniTile(IconData icon, String label, String value, Color color) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: color), 
          const SizedBox(width: 5), 
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.w500))
        ]
      ),
      const SizedBox(height: 7),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
    ],
  );

  // 하단 액션 버튼 디자인
  Widget _actionBtn(String label, IconData icon, VoidCallback onTap) => Column(
    children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 65, height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08), 
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10)
          ),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
    ],
  );

  String _formatDuration(Duration d) => 
      "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
