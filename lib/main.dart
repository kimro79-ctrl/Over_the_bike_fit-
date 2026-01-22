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
  int _maxHeartRate = 0; // 최대 심박수 추적 추가
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  Timer? _watchTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false; 
  List<FlSpot> _hrSpots = [];
  double _timerCounter = 0;
  List<Map<String, dynamic>> _workoutHistory = [];

  void _vibrate() {
    HapticFeedback.lightImpact();
  }

  // 심박수 구간 및 상태 텍스트 반환
  String _getHRStatus() {
    if (!_isWatchConnected) return "연결 대기 중";
    if (!_isWorkingOut) return "준비 완료";
    if (_heartRate >= 160) return "최대 강도 (위험) 🔥";
    if (_heartRate >= 140) return "고강도 유산소 ⚡";
    if (_heartRate >= 120) return "지방 연소 구간 ✨";
    return "가벼운 운동 중 🚲";
  }

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

  void _startHeartRateMonitoring() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!mounted || !_isWatchConnected) return;
      setState(() {
        if (_isWorkingOut) {
          _heartRate = 110 + Random().nextInt(60); 
          // 최대 심박수 갱신
          if (_heartRate > _maxHeartRate) _maxHeartRate = _heartRate;
          
          _timerCounter += 0.2;
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 80) _hrSpots.removeAt(0);
          _calories += 0.035;
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
        _maxHeartRate = _heartRate; // 시작 시점 심박수로 초기화
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
    if (_duration.inSeconds < 2) return;
    
    Map<String, dynamic> record = {
      'date': DateTime.now().toString().substring(5, 16),
      'minutes': _duration.inMinutes,
      'kcal': _calories,
      'maxHR': _maxHeartRate,
    };

    setState(() {
      _workoutHistory.insert(0, record);
      // 저장 후 초기화
      _duration = Duration.zero;
      _calories = 0.0;
      _maxHeartRate = 0;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('기록이 안전하게 저장되었습니다.'),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      )
    );
  }

  Color _getHeartRateColor() {
    if (_heartRate >= 160) return Colors.redAccent;
    if (_heartRate >= 140) return Colors.orangeAccent;
    if (_heartRate >= 120) return Colors.greenAccent;
    return Colors.cyanAccent;
  }

  void _showHistory() {
    _vibrate();
    int totalMinutes = _workoutHistory.fold(0, (sum, item) => sum + (item['minutes'] as int));
    double totalKcal = _workoutHistory.fold(0.0, (sum, item) => sum + (item['kcal'] as double));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('나의 운동 리포트', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.grey[900],
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryTile('횟수', '${_workoutHistory.length}회'),
                    _summaryTile('시간', '${totalMinutes}분'),
                    _summaryTile('칼로리', '${totalKcal.toStringAsFixed(0)}k'),
                  ],
                ),
              ),
              const Divider(height: 30, color: Colors.white10),
              Expanded(
                child: _workoutHistory.isEmpty 
                  ? const Center(child: Text('기록이 없습니다.'))
                  : ListView.builder(
                      itemCount: _workoutHistory.length,
                      itemBuilder: (context, index) {
                        final item = _workoutHistory[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.stars, color: Colors.amberAccent, size: 16),
                          title: Text("${item['date']} | ${item['minutes']}분 | ${item['maxHR']}bpm", 
                            style: const TextStyle(fontSize: 12)),
                          subtitle: Text("${item['kcal'].toStringAsFixed(1)} kcal 소모", style: TextStyle(fontSize: 10, color: Colors.white54)),
                        );
                      },
                    ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
      ),
    );
  }

  Widget _summaryTile(String label, String value) => Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.grey[900]))),
          Positioned.fill(child: Container(color: Colors.white.withOpacity(0.08))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white70)),
                const SizedBox(height: 15),
                
                // 워치 연결 버튼
                GestureDetector(
                  onTap: _isWatchConnected ? null : _handleWatchConnection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: _isWatchConnected ? Colors.black45 : _getHeartRateColor().withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _isWatchConnected ? Colors.white24 : _getHeartRateColor(), width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.watch, color: _isWatchConnected ? Colors.cyanAccent : Colors.white, size: 13),
                        const SizedBox(width: 6),
                        Text(_isWatchConnected ? "워치 데이터 수신 중" : "워치 연결하기", style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 25),
                
                // 현재 운동 상태 텍스트 (추가된 기능)
                Text(_getHRStatus(), style: TextStyle(fontSize: 13, color: _getHeartRateColor(), fontWeight: FontWeight.bold)),

                const SizedBox(height: 15),

                // 그래프 영역
                Container(
                  height: 140,
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: LineChart(LineChartData(
                    minY: 40, maxY: 185,
                    gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 0.5)),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _isWatchConnected && _hrSpots.isNotEmpty ? _hrSpots : [const FlSpot(0, 0)],
                        isCurved: true, barWidth: 2.5, color: _getHeartRateColor(), dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: _isWatchConnected, color: _getHeartRateColor().withOpacity(0.1)),
                      )
                    ],
                  )),
                ),

                const Spacer(),

                // 대시보드
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white10)),
                  child: GridView.count(
                    shrinkWrap: true, crossAxisCount: 2, childAspectRatio: 2.4,
                    children: [
                      _tile('실시간 심박', _isWatchConnected ? '$_heartRate' : '--', Icons.favorite, _getHeartRateColor()),
                      _tile('최대 심박', _isWatchConnected ? '$_maxHeartRate' : '--', Icons.trending_up, Colors.redAccent),
                      _tile('소모 칼로리', '${_calories.toStringAsFixed(1)}', Icons.local_fire_department, Colors.orangeAccent),
                      _tile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blueAccent),
                    ],
                  ),
                ),

                // 하단 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 35, top: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _btn('기록 저장', Icons.save_alt, _saveWorkout),
                      _btn('기록 보기', Icons.bar_chart, _showHistory),
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

  Widget _tile(String l, String v, IconData i, Color c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 12), const SizedBox(width: 5), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60))]),
    const SizedBox(height: 3),
    Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  ]);

  Widget _btn(String l, IconData i, VoidCallback t) => InkWell(onTap: t, child: Container(
    width: 95, height: 55,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), color: Colors.white.withOpacity(0.07), border: Border.all(color: Colors.white12)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 22, color: Colors.white70), const SizedBox(height: 3), Text(l, style: const TextStyle(fontSize: 11))]),
  ));

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
