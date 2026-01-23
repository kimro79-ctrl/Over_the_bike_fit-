import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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

  Future<void> _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.platformName.toLowerCase().contains("fit") || 
            r.advertisementData.serviceUuids.contains(Guid("180D"))) {
          _targetDevice = r.device;
          await FlutterBluePlus.stopScan();
          try {
            await _targetDevice!.connect();
            setState(() => _isWatchConnected = true);
            List<BluetoothService> s = await _targetDevice!.discoverServices();
            for (var service in s) {
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

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _totalHRSum += _heartRate;
          _hrCount++;
          _avgHeartRate = _totalHRSum ~/ _hrCount;
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 30) _hrSpots.removeAt(0); // 콤팩트하게 유지
        }
      });
    }
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            _duration += const Duration(seconds: 1);
            if (_heartRate >= 95) _calories += (_heartRate * 0.0015);
          });
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _saveRecord() {
    if (_duration == Duration.zero) return;
    HapticFeedback.successOverridable();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container(color: Colors.black)))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                const SizedBox(height: 15),
                
                // 1. 워치 연결 버튼
                GestureDetector(
                  onTap: _isWatchConnected ? null : _connectWatch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12), 
                      border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white24),
                      color: Colors.black45
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.watch, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                      const SizedBox(width: 6),
                      Text(_isWatchConnected ? "Connected" : "Connect Watch", style: const TextStyle(fontSize: 11)),
                    ]),
                  ),
                ),

                const SizedBox(height: 10), // 버튼과 그래프 사이 간격 최소화

                // 2. 버튼 바로 밑에 위치한 작은 그래프
                SizedBox(
                  height: 35, // 높이를 더 줄여서 작게 표현
                  width: 120, // 가로 너비도 제한하여 콤팩트하게 배치
                  child: _hrSpots.isNotEmpty 
                    ? LineChart(LineChartData(
                        minY: 40, maxY: 200,
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [LineChartBarData(
                          spots: _hrSpots, isCurved: true, barWidth: 1.5, color: Colors.cyanAccent,
                          dotData: const FlDotData(show: false), 
                          belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1))
                        )]
                      ))
                    : const Center(child: Text("HR Data...", style: TextStyle(fontSize: 8, color: Colors.white24))),
                ),

                const Spacer(),
                _dataPanel(),
                const SizedBox(height: 40),
                _bottomActions(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataPanel() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 25), padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), color: Colors.black87, border: Border.all(color: Colors.white10)),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _dataItem(Icons.favorite, "Heart Rate", _isWatchConnected ? "$_heartRate" : "--", Colors.cyanAccent),
        _dataItem(Icons.analytics, "Average", "$_avgHeartRate", Colors.redAccent),
      ]),
      const SizedBox(height: 30),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _dataItem(Icons.local_fire_department, "Calories", _calories.toStringAsFixed(1), Colors.orangeAccent),
        _dataItem(Icons.timer, "Time", _formatDuration(_duration), Colors.blueAccent),
      ]),
    ]),
  );

  Widget _bottomActions() => Padding(
    padding: const EdgeInsets.only(bottom: 40),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "START", _toggleWorkout),
      _actionBtn(Icons.file_upload_outlined, "SAVE", _saveRecord),
      _actionBtn(Icons.bar_chart, "HISTORY", () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(avgHR: _avgHeartRate, calories: _calories, duration: _duration, hrSpots: _hrSpots)));
      }),
    ]),
  );

  Widget _dataItem(IconData i, String l, String v, Color c) => Column(children: [
    Row(children: [Icon(i, size: 14, color: c), const SizedBox(width: 5), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60))]),
    Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
  ]);

  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [
    GestureDetector(onTap: t, child: Container(width: 65, height: 65, decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)), child: Icon(i, size: 24))),
    const SizedBox(height: 8), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70)),
  ]);

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

// HistoryScreen 클래스는 이전과 동일하게 유지
class HistoryScreen extends StatelessWidget {
  final int avgHR; final double calories; final Duration duration; final List<FlSpot> hrSpots;
  const HistoryScreen({Key? key, required this.avgHR, required this.calories, required this.duration, required this.hrSpots}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Workout Report"), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            height: 200, width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
            child: LineChart(LineChartData(
              minY: 40, maxY: 200, gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
              lineBarsData: [LineChartBarData(spots: hrSpots, isCurved: true, color: Colors.cyanAccent, barWidth: 3, dotData: const FlDotData(show: false))],
            )),
          ),
          const SizedBox(height: 30),
          _tile("Calories", "${calories.toStringAsFixed(1)} kcal", Icons.local_fire_department, Colors.orangeAccent),
          _tile("Avg Heart Rate", "$avgHR BPM", Icons.analytics, Colors.redAccent),
          _tile("Duration", "${duration.inMinutes}m ${duration.inSeconds % 60}s", Icons.timer, Colors.blueAccent),
        ]),
      ),
    );
  }
  Widget _tile(String t, String v, IconData i, Color c) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
    child: Row(children: [Icon(i, color: c, size: 24), const SizedBox(width: 15), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(color: Colors.white60, fontSize: 12)), Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))])]),
  );
}
