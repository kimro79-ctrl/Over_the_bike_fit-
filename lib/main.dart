import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
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
  // 데이터 변수
  int _heartRate = 0;
  int _avgHeartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;

  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  Timer? _timer;
  List<int> _hrHistory = [];
  List<FlSpot> _hrSpots = [const FlSpot(0, 0)];
  double _graphX = 0;

  // 3. 실시간 심박수 연동 로직 (가짜 데이터 -> 실시간 흐름 반영)
  // 실제 워치 SDK 연동 시 이 부분에서 데이터를 수신받도록 구현합니다.
  void _toggleWorkout() {
    if (_isWorkingOut) {
      _timer?.cancel();
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _duration += const Duration(seconds: 1);
          
          if (_isWatchConnected) {
            // 실제 기기 연결 시 수신된 심박수 값을 여기에 대입합니다.
            _heartRate = 130 + Random().nextInt(10) - 5; 
            _hrHistory.add(_heartRate);
            _avgHeartRate = (_hrHistory.reduce((a, b) => a + b) / _hrHistory.length).round();
            _calories += 0.12;

            _graphX += 1;
            _hrSpots.add(FlSpot(_graphX, _heartRate.toDouble()));
            if (_hrSpots.length > 40) _hrSpots.removeAt(0);
          }
        });
      });
    }
    setState(() => _isWorkingOut = !_isWorkingOut);
  }

  Future<void> _connectWatch() async {
    if (await Permission.bluetoothConnect.request().isGranted) {
      setState(() => _isWatchConnected = !_isWatchConnected);
    }
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
              opacity: 0.6,
              child: Image.asset('assets/background.png', fit: BoxFit.cover,
                errorBuilder: (_,__,___)=>Container(color: Colors.blueGrey.withOpacity(0.1)))
            )
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                
                const SizedBox(height: 15),
                
                // 워치 연결 버튼
                GestureDetector(
                  onTap: _connectWatch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white24),
                      color: Colors.black54,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                        const SizedBox(width: 6),
                        Text(_isWatchConnected ? "Amazfit GTS2 mini" : "워치 연결하기", style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),

                // 1. 그래프 사이즈 1/2 축소 및 선 가늘게 수정
                const SizedBox(height: 10),
                SizedBox(
                  height: 60, // 기존 높이의 절반 수준으로 축소
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: _isWatchConnected 
                    ? LineChart(_lineChartData()) 
                    : const Center(child: Text("연결 대기 중...", style: TextStyle(color: Colors.white24, fontSize: 10))),
                ),

                const Spacer(),

                // 데이터 패널
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.black.withOpacity(0.7),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataItem("심박수", _isWatchConnected ? "$_heartRate" : "-", Colors.cyanAccent),
                      _dataItem("심박수평균", _isWatchConnected ? "$_avgHeartRate" : "-", Colors.redAccent),
                      _dataItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _dataItem("운동시간", _formatDuration(_duration), Colors.blueAccent),
                    ],
                  ),
                ),

                // 2, 4. 버튼 아이콘 복구 및 모서리 둥근 사각형 디자인 적용
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionBtn(_isWorkingOut ? Icons.pause_rounded : Icons.play_arrow_rounded, "중지", _toggleWorkout, Colors.orangeAccent),
                      _actionBtn(Icons.save_rounded, "저장", () {}, Colors.white),
                      _actionBtn(Icons.leaderboard_rounded, "기록", () {}, Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataItem(String label, String value, Color color) => Column(
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    ],
  );

  // 4. 모서리가 둥근 사각형 버튼 (작게 교체)
  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, Color color) => Column(
    children: [
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 60, // 버튼 크기 축소
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(15), // 모서리 둥근 사각형
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, size: 30, color: color), // 깨진 아이콘 대신 Material Icon 사용
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
    ],
  );

  // 1. 가느다란 선의 그래프 데이터
  LineChartData _lineChartData() {
    return LineChartData(
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: _hrSpots,
          isCurved: true,
          color: Colors.cyanAccent,
          barWidth: 1.5, // 1. 선 가늘게 수정
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) => 
    "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
