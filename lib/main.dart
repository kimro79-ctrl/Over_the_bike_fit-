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

// 운동 기록 데이터 모델
class WorkoutRecord {
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.date, this.avgHR, this.calories, this.duration);
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
  List<WorkoutRecord> _records = []; // 기록 리스트

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
          if (_hrSpots.length > 50) _hrSpots.removeAt(0); // 2. 그래프 길이 연장 (25->50)
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
    setState(() {
      _records.insert(0, WorkoutRecord(
        DateTime.now().toString().substring(5, 16), 
        _avgHeartRate, _calories, _duration
      ));
    });
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다.")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.6, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container(color: Colors.black)))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                
                GestureDetector(
                  onTap: _isWatchConnected ? null : _connectWatch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10), 
                      border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white24),
                      color: Colors.black45
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.watch, size: 12, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                      const SizedBox(width: 5),
                      Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(fontSize: 10)),
                    ]),
                  ),
                ),

                const SizedBox(height: 10),

                // 2. 실시간 그래프 가로 길이 확장 (width 80 -> 150)
                SizedBox(
                  height: 30, width: 150,
                  child: _hrSpots.isNotEmpty 
                    ? LineChart(LineChartData(
                        minY: 40, maxY: 200, gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
                        lineBarsData: [LineChartBarData(
                          spots: _hrSpots, isCurved: true, barWidth: 1.5, color: Colors.cyanAccent, dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1))
                        )]
                      ))
                    : const SizedBox(),
                ),

                const Spacer(),
                
                // 3. 데이터 배너 (배경 더 흐리게 조정 opacity 0.87 -> 0.6)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25), padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), color: Colors.black.withOpacity(0.6), border: Border.all(color: Colors.white10)),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _dataItem(Icons.favorite, "현재 심박수", _isWatchConnected ? "$_heartRate" : "--", Colors.cyanAccent),
                      _dataItem(Icons.analytics, "평균 심박수", "$_avgHeartRate", Colors.redAccent),
                    ]),
                    const SizedBox(height: 30),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _dataItem(Icons.local_fire_department, "칼로리 소모", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _dataItem(Icons.timer, "운동 시간", _formatDuration(_duration), Colors.blueAccent),
                    ]),
                  ]),
                ),

                const SizedBox(height: 40),
                
                // 5. 버튼 한글화
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", _toggleWorkout),
                    _actionBtn(Icons.file_upload_outlined, "저장", _saveRecord),
                    _actionBtn(Icons.bar_chart, "기록", () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(records: _records, hrSpots: _hrSpots)));
                    }),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

// 4. 운동 기록 페이지 수정
class HistoryScreen extends StatelessWidget {
  final List<WorkoutRecord> records;
  final List<FlSpot> hrSpots;
  const HistoryScreen({Key? key, required this.records, required this.hrSpots}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("운동 리포트"), backgroundColor: Colors.transparent),
      body: Column(
        children: [
          // 4-1. 그래프 사이즈 1/2로 축소 (height 200 -> 100)
          Container(
            height: 100, width: double.infinity, margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
            child: LineChart(LineChartData(
              minY: 40, maxY: 200, gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
              lineBarsData: [LineChartBarData(spots: hrSpots, isCurved: true, color: Colors.cyanAccent, barWidth: 2, dotData: const FlDotData(show: false))],
            )),
          ),
          
          // 4-2. 기록 리스트 추가
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft, child: Text("과거 기록 리스트", style: TextStyle(color: Colors.white60, fontSize: 14))),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final r = records[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.date, style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                        Text("${r.duration.inMinutes}분 ${r.duration.inSeconds % 60}초", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ]),
                      Text("${r.avgHR} BPM", style: const TextStyle(fontSize: 16)),
                      Text("${r.calories.toStringAsFixed(1)} kcal", style: const TextStyle(color: Colors.orangeAccent)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
