import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:table_calendar/table_calendar.dart';

void main() => runApp(const BikeFitApp());

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
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
  double _calories = 0.0;
  List<FlSpot> _hrSpots = [const FlSpot(0, 0)];
  Duration _duration = Duration.zero;
  Timer? _timer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;

  @override
  void initState() {
    super.initState();
    _initApp(); // 권한 요청 실행
  }

  Future<void> _initApp() async {
    // 앱 실행 시 필수 권한 요청
    await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.sensors,
      Permission.location,
    ].request();
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            _duration += const Duration(seconds: 1);
            if (_heartRate >= 85) _calories += (_heartRate * 0.0005);
          });
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _isWorkingOut = false;
      _duration = Duration.zero;
      _calories = 0.0;
      _heartRate = 0;
      _avgHeartRate = 0;
      _hrSpots = [const FlSpot(0, 0)];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.png'),
            fit: BoxFit.cover,
            opacity: 0.4, // 배경을 어둡게 처리하여 UI 강조
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 상단 타이틀 + 그래프 섹션
              _buildHeaderWithGraph(),
              
              const Spacer(), // 가운데 자전거 이미지 삭제로 생긴 공간

              // 데이터 표시 판넬 (4개 지표)
              _buildStatsPanel(),

              const SizedBox(height: 30),

              // 하단 버튼부
              _buildControlButtons(),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 상단 타이틀과 그 바로 아래 작은 그래프
  Widget _buildHeaderWithGraph() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Indoor Bike Fit", 
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              _buildConnectChip(),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            height: 100,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(15),
            ),
            child: _isWatchConnected 
              ? LineChart(_chartConfig()) 
              : const Center(child: Text("워치를 연결하면 실시간 그래프가 표시됩니다.")),
          ),
        ],
      ),
    );
  }

  // 빌드 에러의 원인이었던 _dataItem 함수를 다시 정의함
  Widget _dataItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatsPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _dataItem("심박수", "$_heartRate", Colors.greenAccent),
          _dataItem("평균", "$_avgHeartRate", Colors.redAccent),
          _dataItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
          _dataItem("운동시간", _formatDuration(_duration), Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleButton(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", _toggleWorkout),
        _circleButton(Icons.refresh, "리셋", _reset),
        _circleButton(Icons.save, "저장", () {}),
        _circleButton(Icons.calendar_month, "기록", () {
          Navigator.push(context, MaterialPageRoute(builder: (c) => const HistoryScreen()));
        }),
      ],
    );
  }

  // 보조 위젯들
  Widget _buildConnectChip() {
    return ActionChip(
      label: Text(_isWatchConnected ? "연결됨" : "워치 연결"),
      onPressed: () => setState(() => _isWatchConnected = !_isWatchConnected),
      backgroundColor: _isWatchConnected ? Colors.cyanAccent.withOpacity(0.2) : Colors.white10,
    );
  }

  Widget _circleButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white12,
              border: Border.all(color: Colors.white10),
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
      ],
    );
  }

  LineChartData _chartConfig() {
    return LineChartData(
      gridData: FlGridData(show: false),
      titlesData: FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: _hrSpots, isCurved: true, color: Colors.cyanAccent, barWidth: 2, dotData: FlDotData(show: false),
        )
      ],
    );
  }

  String _formatDuration(Duration d) => "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

// 기록 리포트 화면
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("기록 리포트")),
      body: const Center(child: Text("저장된 기록이 없습니다.")),
    );
  }
}
