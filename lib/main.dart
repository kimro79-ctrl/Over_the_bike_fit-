import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 스플래시 대기 시간
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

class _WorkoutScreenState extends State<WorkoutScreen> with SingleTickerProviderStateMixin {
  int _heartRate = 0; 
  int _maxHeartRate = 0;
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
  String _watchStatus = "워치 연결";

  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _workoutTimer?.cancel();
    _watchTimer?.cancel();
    super.dispose();
  }

  void _vibrate() => HapticFeedback.lightImpact();

  // 한글 상태 메시지
  String _getHRStatus() {
    if (!_isWatchConnected) return "워치 연결 안 됨";
    if (!_isWorkingOut) return "라이딩 준비 완료";
    if (_heartRate >= 160) return "최대 강도 🔥";
    if (_heartRate >= 140) return "무산소 구간 ⚡";
    if (_heartRate >= 120) return "지방 연소 ✨";
    return "웜업 중 🚲";
  }

  Color _getHeartRateColor() {
    if (_heartRate >= 160) return Colors.redAccent;
    if (_heartRate >= 140) return Colors.orangeAccent;
    if (_heartRate >= 120) return Colors.greenAccent;
    return Colors.cyanAccent;
  }

  // [수정] 워치 연결 시 클릭된 레이어 간섭 제거
  Future<void> _handleWatchConnection() async {
    _vibrate();
    if (await Permission.bluetoothConnect.request().isGranted) {
      setState(() {
        _isWatchConnected = true;
        _watchStatus = "연결됨";
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
          _heartRate = 110 + Random().nextInt(60); 
          if (_heartRate > _maxHeartRate) _maxHeartRate = _heartRate;
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
        _totalHRSum = 0; _hrCount = 0; _avgHeartRate = 0;
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _duration += const Duration(seconds: 1));
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _saveWorkout() {
    _vibrate();
    if (_duration.inSeconds < 5) return;
    setState(() { _duration = Duration.zero; _calories = 0.0; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다."), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 배경 이미지
          Positioned.fill(child: Opacity(opacity: 0.2, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container()))),
          
          // 2. 하단 그라데이션 오버레이 (배경과 UI 조화)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                ),
              ),
            ),
          ),

          // 3. 메인 데이터 레이아웃
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                Text('Over The Bike Fit', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white.withOpacity(0.9))),
                const SizedBox(height: 15),
                
                // [수정] 작고 세련된 워치 연결 버튼
                if (!_isWatchConnected)
                  GestureDetector(
                    onTap: _handleWatchConnection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 0.5),
                        color: Colors.black.withOpacity(0.4),
                      ),
                      child: Text(_watchStatus, style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),

                const SizedBox(height: 30),

                // 중앙 심박수 디스플레이
                ScaleTransition(
                  scale: _heartRate >= 160 ? _blinkController.drive(Tween(begin: 1.0, end: 1.1)) : const AlwaysStoppedAnimation(1.0),
                  child: Text(
                    _isWatchConnected ? '$_heartRate' : '--',
                    style: TextStyle(fontSize: 100, fontWeight: FontWeight.w900, color: _getHeartRateColor(), height: 1.1),
                  ),
                ),
                Text(_getHRStatus(), style: TextStyle(color: _getHeartRateColor().withOpacity(0.8), fontWeight: FontWeight.bold, fontSize: 13)),

                const SizedBox(height: 40),

                // [수정] 초미세 가느다란 그래프 (barWidth: 0.8)
                // 아래 부분에서 const 키워드를 제거했습니다.
                SizedBox(
                  height: 60,
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: LineChart(LineChartData(
                    minY: 40, maxY: 190,
                    gridData: FlGridData(show: false),     // const 제거
                    titlesData: FlTitlesData(show: false), // const 제거
                    borderData: FlBorderData(show: false), // const 제거 (여기가 오류 원인이었습니다)
                    lineBarsData: [
                      LineChartBarData(
                        spots: _hrSpots.isEmpty ? [const FlSpot(0, 70)] : _hrSpots,
                        isCurved: true, barWidth: 0.8, color: _getHeartRateColor().withOpacity(0.8), dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [_getHeartRateColor().withOpacity(0.2), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                      )
                    ],
                  )),
                ),

                const Spacer(),

                // [수정] 어두운 데이터 배너
                Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  padding: const EdgeInsets.symmetric(vertical: 25),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: Colors.black.withOpacity(0.85),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataBox("평균", "$_avgHeartRate"),
                      _dataBox("최대", "$_maxHeartRate"),
                      _dataBox("칼로리", _calories.toStringAsFixed(1)),
                      _dataBox("시간", _formatDuration(_duration)),
                    ],
                  ),
                ),
                const SizedBox(height: 160), // 하단 버튼 공간 확보
              ],
            ),
          ),

          // 4. [수정] 최상단 독립 버튼 레이어 (먹통 해결용)
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _actionPillBtn(_isWorkingOut ? Icons.stop : Icons.play_arrow, _isWorkingOut ? "중지" : "시작", _toggleWorkout, _isWorkingOut ? Colors.redAccent : Colors.greenAccent),
                const SizedBox(width: 15),
                _actionPillBtn(Icons.save, "저장", _saveWorkout, Colors.white70),
                const SizedBox(width: 15),
                _actionPillBtn(Icons.history, "기록", () {}, Colors.white70),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataBox(String label, String value) => Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38)),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
    ],
  );

  // [수정] 캡슐형 버튼 디자인 (이미지 가이드 반영)
  Widget _actionPillBtn(IconData icon, String label, VoidCallback onTap, Color color) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      width: 100, height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
