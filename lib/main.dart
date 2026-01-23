import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart'; // 요일 표시를 위한 패키지 (기본 제공)

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BikeFitApp());
}

class WorkoutRecord {
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.date, this.avgHR, this.calories, this.duration);
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
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  
  BluetoothDevice? _targetDevice;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false; 
  List<FlSpot> _hrSpots = []; 
  double _timeCounter = 0;
  List<WorkoutRecord> _records = []; 

  Future<void> _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StreamBuilder<List<ScanResult>>(
        stream: FlutterBluePlus.scanResults,
        builder: (context, snapshot) {
          final results = snapshot.data ?? [];
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(15),
                child: Text("연결할 기기 선택", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final r = results[index];
                    final name = r.device.platformName.isEmpty ? "Unknown Device" : r.device.platformName;
                    return ListTile(
                      leading: const Icon(Icons.watch, color: Colors.cyanAccent),
                      title: Text(name),
                      subtitle: Text(r.device.remoteId.str),
                      onTap: () async {
                        await r.device.connect();
                        _setupDevice(r.device);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() {
      _targetDevice = device;
      _isWatchConnected = true;
    });
    List<BluetoothService> services = await device.discoverServices();
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
  }

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 120) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
          if (_heartRate >= 95) {
            _calories += (_heartRate * 0.6309 * (1/60) * 0.2);
          }
        }
      });
    }
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() { _duration += const Duration(seconds: 1); });
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _saveRecord() {
    if (_duration == Duration.zero) return;

    // 한국어 요일 구하기
    List<String> weekDays = ["", "월", "화", "수", "목", "금", "토", "일"];
    DateTime now = DateTime.now();
    String formattedDate = "${now.month}/${now.day}(${weekDays[now.weekday]})";

    setState(() {
      _records.insert(0, WorkoutRecord(
        formattedDate, 
        _avgHeartRate, _calories, _duration
      ));
    });

    HapticFeedback.lightImpact();
    // ✅ 팝업 노출 시간을 1초로 짧게 설정
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("운동 기록이 저장되었습니다!"),
        duration: Duration(seconds: 1),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ✅ 배경 이미지 투명도를 0.8로 올려서 더 밝게 만듦
          Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container(color: Colors.black)))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
                const SizedBox(height: 15),
                
                GestureDetector(
                  onTap: _isWatchConnected ? null : _connectWatch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12), 
                      border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                      color: Colors.black54
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.watch, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                      const SizedBox(width: 6),
                      Text(_isWatchConnected ? "연결 완료" : "워치 연결하기", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  height: 35, width: 220,
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
                
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25), padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), color: Colors.black.withOpacity(0.6), border: Border.all(color: Colors.white24)),
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
                
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작/중지", _toggleWorkout),
                    _actionBtn(Icons.file_upload_outlined, "기록저장", _saveRecord),
                    _actionBtn(Icons.bar_chart, "기록보기", () {
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
    Row(children: [Icon(i, size: 14, color: c), const SizedBox(width: 5), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]),
    Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
  ]);

  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [
    GestureDetector(onTap: t, child: Container(width: 65, height: 65, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white24)), child: Icon(i, size: 24, color: Colors.white))),
    const SizedBox(height: 8), Text(l, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
  ]);

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

class HistoryScreen extends StatelessWidget {
  final List<WorkoutRecord> records;
  final List<FlSpot> hrSpots;
  const HistoryScreen({Key? key, required this.records, required this.hrSpots}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double currentCal = records.isNotEmpty ? records.first.calories : 0.0;
    double goalProgress = (currentCal / 300).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("운동 리포트", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.white.withOpacity(0.08), Colors.transparent], begin: Alignment.topLeft),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 100,
                    child: LineChart(LineChartData(
                      minY: 40, maxY: 200, gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
                      lineBarsData: [LineChartBarData(spots: hrSpots.isNotEmpty ? hrSpots : [const FlSpot(0, 0)], isCurved: true, color: Colors.cyanAccent, barWidth: 2, dotData: const FlDotData(show: false))],
                    )),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _reportStat("운동시간", records.isNotEmpty ? "${records.first.duration.inMinutes}분" : "0분"),
                      _reportStat("소모칼로리", "${currentCal.toInt()}kcal"),
                      _reportStat("평균심박", records.isNotEmpty ? "${records.first.avgHR}" : "0"),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("오늘의 목표 달성률", style: TextStyle(fontSize: 11, color: Colors.white54)),
                          Text("${(goalProgress * 100).toInt()}%", style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: goalProgress, backgroundColor: Colors.white10, color: Colors.cyanAccent, minHeight: 4),
                    ],
                  )
                ],
              ),
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10),
              child: Align(alignment: Alignment.centerLeft, child: Text("운동 히스토리", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyanAccent))),
            ),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final r = records[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.directions_bike, color: Colors.cyanAccent, size: 18),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // ✅ 일자 및 요일 표시 (예: 1/23(금))
                          Text(r.date, style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          Text("${r.duration.inMinutes}분 운동 완료", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ]),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("${r.avgHR} BPM", style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          Text("${r.calories.toInt()} kcal", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _reportStat(String label, String value) => Column(
    children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    ],
  );
}
