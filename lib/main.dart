import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
  
  BluetoothDevice? _targetDevice;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false; 
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;

  // 로직 분리: 워치 연결 전용
  Future<void> _connectWatch() async {
    HapticFeedback.mediumImpact();
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.platformName.contains("Amazfit") || r.advertisementData.serviceUuids.contains(Guid("180D"))) {
          _targetDevice = r.device;
          FlutterBluePlus.stopScan();
          try {
            await _targetDevice!.connect();
            setState(() => _isWatchConnected = true);
            List<BluetoothService> services = await _targetDevice!.discoverServices();
            for (var service in services) {
              if (service.uuid == Guid("180D")) {
                for (var char in service.characteristics) {
                  if (char.uuid == Guid("2A37")) {
                    await char.setNotifyValue(true);
                    char.lastValueStream.listen((value) => _decodeHR(value));
                  }
                }
              }
            }
          } catch (e) { debugPrint(e.toString()); }
        }
      }
    });
  }

  // 로직 분리: 운동 시작/중지 및 칼로리 제한 적용
  void _toggleWorkout() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _duration += const Duration(seconds: 1);
            // 심박수가 95 BPM 이상일 때만 칼로리 증가
            if (_isWatchConnected && _heartRate >= 95) {
              _calories += (_heartRate * 0.0015);
            }
          });
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    int flag = data[0];
    int hr = (flag & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _totalHRSum += _heartRate;
          _hrCount++;
          _avgHeartRate = _totalHRSum ~/ _hrCount;
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _workoutTimer?.cancel();
    _targetDevice?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 배경 밝기 향상 (0.7)
          Positioned.fill(
            child: Opacity(
              opacity: 0.7, 
              child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container(color: Colors.black))
            )
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 30),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 20),
                
                // 워치 연결 버튼
                GestureDetector(
                  onTap: _isWatchConnected ? null : _connectWatch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20), 
                      border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white24), 
                      color: Colors.black.withOpacity(0.5)
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.watch, size: 16, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                      const SizedBox(width: 8),
                      Text(_isWatchConnected ? "연결됨: ${_targetDevice?.platformName}" : "워치 찾기 및 연결", style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
                ),

                // 그래프: 토글 밑 배치 + 크기 축소
                const SizedBox(height: 15),
                SizedBox(
                  height: 40, 
                  width: double.infinity,
                  child: _isWatchConnected && _hrSpots.isNotEmpty 
                    ? LineChart(LineChartData(
                        minY: 40, maxY: 200,
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [LineChartBarData(spots: _hrSpots, isCurved: true, barWidth: 1.5, color: Colors.cyanAccent, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)))]
                      ))
                    : const Center(child: Text("데이터 대기 중...", style: TextStyle(fontSize: 10, color: Colors.white24))),
                ),

                const Spacer(),
                
                // 데이터 보드
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25),
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), color: Colors.black.withOpacity(0.7), border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _dataItem(Icons.favorite, "실시간 심박", _isWatchConnected ? "$_heartRate" : "--", Colors.cyanAccent),
                      _dataItem(Icons.analytics, "평균 심박수", _isWatchConnected ? "$_avgHeartRate" : "--", Colors.redAccent),
                    ]),
                    const SizedBox(height: 30),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _dataItem(Icons.local_fire_department, "소모 칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _dataItem(Icons.timer, "운동 시간", _formatDuration(_duration), Colors.blueAccent),
                    ]),
                  ]),
                ),
                
                const SizedBox(height: 40),

                // 하단 액션 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, _isWorkingOut ? "중지" : "시작", _toggleWorkout),
                    _actionBtn(Icons.file_upload_outlined, "저장", () {}),
                    _actionBtn(Icons.bar_chart, "기록", () {}),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataItem(IconData icon, String label, String value, Color color) => Column(children: [
    Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 5), Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60))]),
    const SizedBox(height: 8),
    Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
  ]);

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) => Column(children: [
    GestureDetector(onTap: onTap, child: Container(width: 70, height: 70, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(0.1))), child: Icon(icon, size: 28, color: Colors.white))),
    const SizedBox(height: 10),
    Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
  ]);

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
