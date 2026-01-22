import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

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
  int _heartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _timer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = [const FlSpot(0, 70)];
  double _timerCounter = 0;

  Future<void> _handleWatchConnection() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    if (statuses.values.any((s) => s.isPermanentlyDenied || s.isDenied)) {
      openAppSettings();
    } else {
      setState(() {
        _isWatchConnected = true;
        _heartRate = 72;
      });
      _startDataStream();
    }
  }

  void _startDataStream() {
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || !_isWatchConnected) t.cancel();
      setState(() {
        if (_isWorkingOut) {
          _heartRate = 85 + Random().nextInt(45);
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 25) _hrSpots.removeAt(0);
          if (_heartRate >= 90) _calories += 0.08;
        } else {
          _heartRate = 65 + Random().nextInt(10);
        }
      });
    });
  }

  void _toggleWorkout() {
    if (!_isWatchConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('워치를 먼저 연결해주세요')));
      return;
    }
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() { _duration += const Duration(seconds: 1); _timerCounter++; });
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover, 
            errorBuilder: (_,__,___) => Container(color: Colors.black))),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                const Text('Over The Bike Fit', 
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.white70)),
                
                // 워치 연결 버튼
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 20),
                  child: InkWell(
                    onTap: _handleWatchConnection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white24),
                        color: Colors.black.withOpacity(0.4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.watch, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                          const SizedBox(width: 6),
                          Text(_isWatchConnected ? "워치 연결됨" : "워치 연결 및 권한 설정", 
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. 그래프 (컬러 밸런스 조정 및 시인성 강화)
                Container(
                  height: MediaQuery.of(context).size.height * 0.22,
                  margin: const EdgeInsets.symmetric(horizontal: 25),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4), // 그래프 배경 마스크
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: LineChart(LineChartData(
                    minY: 50, maxY: 150,
                    lineBarsData: [LineChartBarData(
                      spots: _isWatchConnected ? _hrSpots : [const FlSpot(0, 0)],
                      isCurved: true, 
                      color: Colors.cyanAccent, // 👈 붉은색 대신 시원하고 눈에 띄는 사이언 컬러
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true, 
                        gradient: LinearGradient(
                          colors: [Colors.cyanAccent.withOpacity(0.3), Colors.cyanAccent.withOpacity(0.0)],
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        )
                      )
                    )],
                    titlesData: const FlTitlesData(show: false),
                    gridData: FlGridData(
                      show: true, 
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                  )),
                ),

                const Spacer(),

                // 3. 데이터 타일 (버튼 바로 위 배치)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 45),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 2.8,
                    children: [
                      _compactTile('심박수', '$_heartRate BPM', Icons.favorite, Colors.redAccent),
                      _compactTile('칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orangeAccent),
                      _compactTile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blueAccent),
                      _compactTile('상태', _heartRate >= 90 ? '고강도' : '안정', Icons.bolt, Colors.amberAccent),
                    ],
                  ),
                ),

                // 4. 버튼 (축소된 블랙 그라데이션)
                Padding(
                  padding: const EdgeInsets.only(bottom: 35, top: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _miniGradButton(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _miniGradButton('저장', Icons.save, () {}),
                      _miniGradButton('기록 보기', Icons.history, () {}),
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

  Widget _compactTile(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ],
        ),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  Widget _miniGradButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 90,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFF3A3A3A), Color(0xFF000000)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
