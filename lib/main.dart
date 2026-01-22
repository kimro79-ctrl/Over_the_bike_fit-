import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 진동 기능을 위한 라이브러리
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 스플래시 화면 2초 대기
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
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  Timer? _watchTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false; 
  List<FlSpot> _hrSpots = [];
  double _timerCounter = 0;
  List<String> _workoutHistory = [];

  // 진동 피드백 (조작감 향상)
  void _vibrate() {
    HapticFeedback.lightImpact();
  }

  // 워치 연결 로직
  Future<void> _handleWatchConnection() async {
    _vibrate();
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    if (statuses.values.every((status) => status.isGranted)) {
      setState(() {
        _isWatchConnected = true;
        _heartRate = 72;
        _hrSpots = [const FlSpot(0, 72)];
      });
      _startHeartRateMonitoring();
    } else {
      await openAppSettings();
    }
  }

  // 심박수 모니터링 (0.2초 간격 디테일 그래프)
  void _startHeartRateMonitoring() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!mounted || !_isWatchConnected) return;
      setState(() {
        if (_isWorkingOut) {
          // 운동 중 심박수 시뮬레이션
          _heartRate = 115 + Random().nextInt(50); 
          _timerCounter += 0.2;
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 80) _hrSpots.removeAt(0);
          _calories += 0.03;
        } else {
          _heartRate = 65 + Random().nextInt(10);
        }
      });
    });
  }

  // 운동 시작/정지
  void _toggleWorkout() {
    _vibrate();
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _duration += const Duration(seconds: 1));
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  // 기록 저장
  void _saveWorkout() {
    _vibrate();
    if (_duration.inSeconds < 1) return;
    String record = "${DateTime.now().toString().substring(5, 16)} | ${_duration.inMinutes}분 | ${_calories.toStringAsFixed(1)}kcal";
    setState(() => _workoutHistory.insert(0, record));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('기록이 저장되었습니다.'),
        duration: const Duration(milliseconds: 1500), // 짧은 노출 시간
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 100, left: 50, right: 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      )
    );
  }

  // 심박수 구간별 색상 변경
  Color _getHeartRateColor() {
    if (_heartRate >= 155) return Colors.redAccent;    // 고강도
    if (_heartRate >= 130) return Colors.orangeAccent; // 중강도
    return Colors.cyanAccent;                          // 안정/저강도
  }

  // 기록 보기 팝업
  void _showHistory() {
    _vibrate();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('운동 기록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.grey[900],
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _workoutHistory.isEmpty 
            ? const Center(child: Text('기록이 없습니다.'))
            : ListView.builder(
                itemCount: _workoutHistory.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.history, color: Colors.cyanAccent, size: 18),
                  title: Text(_workoutHistory[index], style: const TextStyle(fontSize: 12)),
                  dense: true,
                ),
              ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 배경 이미지 + 밝기 레이어
          Positioned.fill(
            child: Image.asset('assets/background.png', fit: BoxFit.cover, 
              errorBuilder: (_,__,___) => Container(color: Colors.grey[900])),
          ),
          Positioned.fill(
            child: Container(color: Colors.white.withOpacity(0.08)), // 전체 배경 밝기 미세 상향
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // 제목 크기 축소
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                
                const SizedBox(height: 20),
                
                // 더 작고 정갈해진 워치 연결 버튼
                GestureDetector(
                  onTap: _isWatchConnected ? null : _handleWatchConnection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isWatchConnected ? Colors.black45 : _getHeartRateColor().withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isWatchConnected ? Colors.white24 : _getHeartRateColor(),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_searching, color: _isWatchConnected ? Colors.cyanAccent : Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          _isWatchConnected ? "워치 연결됨" : "워치 연결하기",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 35),

                // 실시간 구간별 색상 그래프
                Container(
                  height: 150,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: LineChart(LineChartData(
                    minY: 40, maxY: 180,
                    gridData: FlGridData(show: true, drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.08), strokeWidth: 0.5)),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _isWatchConnected && _hrSpots.isNotEmpty ? _hrSpots : [const FlSpot(0, 0)],
                        isCurved: true,
                        barWidth: 2.5,
                        color: _getHeartRateColor(),
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: _isWatchConnected,
                          color: _getHeartRateColor().withOpacity(0.12)
                        ),
                      )
                    ],
                  )),
                ),

                const Spacer(),

                // 대시보드 데이터 타일
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.white10)
                  ),
                  child: GridView.count(
                    shrinkWrap: true, crossAxisCount: 2, childAspectRatio: 2.3,
                    children: [
                      _tile('심박수', _isWatchConnected ? '$_heartRate BPM' : '--', Icons.favorite, _getHeartRateColor()),
                      _tile('칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orangeAccent),
                      _tile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blueAccent),
                      _tile('상태', _isWorkingOut ? '운동 중' : '대기', Icons.bolt, Colors.amberAccent),
                    ],
                  ),
                ),

                // 하단 메인 버튼 세트
                Padding(
                  padding: const EdgeInsets.only(bottom: 40, top: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _btn('저장', Icons.save, _saveWorkout),
                      _btn('기록 보기', Icons.history, _showHistory),
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

  Widget _tile(String l, String v, IconData i, Color c) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 12), const SizedBox(width: 5), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60))]),
      const SizedBox(height: 4),
      Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  ]);

  Widget _btn(String l, IconData i, VoidCallback t) => InkWell(onTap: t, child: Container(
    width: 95, height: 55,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), color: Colors.white.withOpacity(0.08), border: Border.all(color: Colors.white12)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 22), const SizedBox(height: 3), Text(l, style: const TextStyle(fontSize: 11))]),
  ));

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
