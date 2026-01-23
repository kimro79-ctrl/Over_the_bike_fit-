import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 가로 모드 방지
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const BikeFitApp());
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Pretendard', // 폰트가 있다면 적용, 없다면 기본폰트 사용
      ),
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
  // --- 상태 변수 ---
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

  // --- 4. 워치 연결 및 권한 설정 로직 ---
  Future<void> _handleWatchConnection() async {
    // Android 12 이상을 위한 근처 기기(Nearby Devices) 권한 포함
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothConnect]!.isGranted &&
        statuses[Permission.bluetoothScan]!.isGranted) {
      setState(() {
        _isWatchConnected = !_isWatchConnected;
        if (!_isWatchConnected) {
          _heartRate = 0;
          _hrSpots = [const FlSpot(0, 0)];
          _graphX = 0;
        }
      });
      _showToast(_isWatchConnected ? "워치가 연결되었습니다." : "워치 연결 해제");
    } else {
      _showToast("블루투스 및 근처 기기 권한이 필요합니다.");
    }
  }

  // --- 3 & 6. 운동 로직 (워치와 분리) ---
  void _toggleWorkout() {
    if (_isWorkingOut) {
      _timer?.cancel();
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _duration += const Duration(seconds: 1);
          
          // 워치 연결 시에만 데이터 및 그래프 작동
          if (_isWatchConnected) {
            _heartRate = 135 + Random().nextInt(15) - 7; // 시뮬레이션 데이터
            _hrHistory.add(_heartRate);
            _avgHeartRate = (_hrHistory.reduce((a, b) => a + b) / _hrHistory.length).round();
            _calories += 0.13;

            _graphX += 1;
            _hrSpots.add(FlSpot(_graphX, _heartRate.toDouble()));
            if (_hrSpots.length > 30) _hrSpots.removeAt(0);
          }
        });
      });
    }
    setState(() => _isWorkingOut = !_isWorkingOut);
  }

  // --- 6. 팝업 짧게 노출 ---
  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        duration: const Duration(milliseconds: 1000),
        behavior: SnackBarBehavior.floating,
        width: 200,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 2. 뒷배경 밝게 수정 (Opacity 0.6)
          Positioned.fill(
            child: Opacity(
              opacity: 0.6,
              child: Image.asset(
                'assets/background.png', 
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => 
                  Container(color: Colors.red.withOpacity(0.1)), // 이미지 없을 시 대비
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // 4. 타이틀 작게
                const Text('Over The Bike Fit', 
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white54, letterSpacing: 2)),
                
                const SizedBox(height: 15),
                
                // 5. 워치 연결 버튼 (세련된 컬러 교체)
                GestureDetector(
                  onTap: _handleWatchConnection,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: _isWatchConnected ? Colors.cyanAccent.withOpacity(0.15) : Colors.black54,
                      border: Border.all(
                        color: _isWatchConnected ? Colors.cyanAccent : Colors.white24,
                        width: 1,
                      ),
                      boxShadow: _isWatchConnected ? [
                        BoxShadow(color: Colors.cyanAccent.withOpacity(0.2), blurRadius: 10)
                      ] : [],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.watch_rounded, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white70),
                        const SizedBox(width: 8),
                        Text(
                          _isWatchConnected ? "Amazfit GTS2 mini" : "Connect Watch",
                          style: TextStyle(fontSize: 11, color: _isWatchConnected ? Colors.cyanAccent : Colors.white70, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

                // 1. 워치연결버튼 아래 미니 그래프
                const SizedBox(height: 20),
                SizedBox(
                  height: 80, 
                  width: MediaQuery.of(context).size.width * 0.85,
                  child: _isWatchConnected 
                    ? LineChart(_miniChartData())
                    : const Center(child: Text("워치를 연결하면 그래프가 표시됩니다.", style: TextStyle(color: Colors.white24, fontSize: 10))),
                ),

                const Spacer(),

                // 5. 데이터 패널 (심박수/심박수평균/칼로리/운동시간)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(vertical: 25),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: Colors.black.withOpacity(0.7),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataColumn("심박수", _isWatchConnected ? "$_heartRate" : "-", Colors.cyanAccent),
                      _dataColumn("심박수평균", _isWatchConnected ? "$_avgHeartRate" : "-", Colors.redAccent),
                      _dataColumn("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _dataColumn("운동시간", _formatDuration(_duration), Colors.blueAccent),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),

                // 1 & 7. 버튼 아이콘 수정 (깨짐 방지)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _circleBtn(
                        _isWorkingOut ? Icons.pause_rounded : Icons.play_arrow_rounded, 
                        _isWorkingOut ? "중지" : "시작", 
                        _toggleWorkout, 
                        _isWorkingOut ? Colors.orangeAccent : Colors.cyanAccent
                      ),
                      _circleBtn(Icons.save_rounded, "저장", () => _showToast("데이터 저장 완료"), Colors.white),
                      _circleBtn(Icons.bar_chart_rounded, "기록", () => _showToast("기록 리스트"), Colors.white),
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

  Widget _dataColumn(String label, String value, Color color) => Column(
    children: [
      Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
    ],
  );

  Widget _circleBtn(IconData icon, String label, VoidCallback onTap, Color color) => Column(
    children: [
      GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.1),
            border: Border.all(color: Colors.white10),
          ),
          child: Icon(icon, size: 35, color: color),
        ),
      ),
      const SizedBox(height: 10),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
    ],
  );

  LineChartData _miniChartData() {
    return LineChartData(
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: _hrSpots,
          isCurved: true,
          color: Colors.cyanAccent,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true, 
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.cyanAccent.withOpacity(0.3), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds % 60)}";
  }
}
