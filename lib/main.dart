import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recordsJson = prefs.getString('workout_records');
    if (recordsJson != null) {
      final List<dynamic> decodedList = jsonDecode(recordsJson);
      setState(() {
        _records = decodedList.map((item) => WorkoutRecord(
          item['date'],
          item['avgHR'],
          item['calories'],
          Duration(seconds: item['durationSeconds']),
        )).toList();
      });
    }
  }

  Future<void> _saveRecordsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> recordList = _records.map((r) => {
      'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds,
    }).toList();
    await prefs.setString('workout_records', jsonEncode(recordList));
  }

  void _resetWorkout() {
    if (_isWorkingOut) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동을 먼저 중지해주세요."), duration: Duration(seconds: 1)));
      return;
    }
    setState(() {
      _duration = Duration.zero; _calories = 0.0; _avgHeartRate = 0; _hrSpots = []; _timeCounter = 0;
    });
    HapticFeedback.mediumImpact();
  }

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
          final results = (snapshot.data ?? []).where((r) => r.device.platformName.isNotEmpty).toList();
          return Column(
            children: [
              const Padding(padding: EdgeInsets.all(15), child: Text("연결할 워치 선택", style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: results.isEmpty ? const Center(child: Text("주변에 감지된 워치가 없습니다.")) : ListView.builder(itemCount: results.length, itemBuilder: (context, index) {
                final r = results[index];
                return ListTile(leading: const Icon(Icons.watch, color: Colors.cyanAccent), title: Text(r.device.platformName), onTap: () async {
                  await r.device.connect(); _setupDevice(r.device); Navigator.pop(context);
                });
              })),
            ],
          );
        },
      ),
    );
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() { _targetDevice = device; _isWatchConnected = true; });
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
          if (_heartRate >= 95) _calories += (_heartRate * 0.6309 * (1/60) * 0.2);
        }
      });
    }
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => _duration += const Duration(seconds: 1)));
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _saveRecord() async {
    if (_duration == Duration.zero) return;
    List<String> weekDays = ["", "월", "화", "수", "목", "금", "토", "일"];
    DateTime now = DateTime.now();
    String formattedDate = "${now.month}/${now.day}(${weekDays[now.weekday]})";
    setState(() { _records.insert(0, WorkoutRecord(formattedDate, _avgHeartRate, _calories, _duration)); });
    await _saveRecordsToStorage();
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록이 저장되었습니다!"), duration: Duration(seconds: 1)));
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
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                GestureDetector(onTap: _isWatchConnected ? null : _connectWatch, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white), color: Colors.black54), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.watch, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white), const SizedBox(width: 6), Text(_isWatchConnected ? "연결 완료" : "워치 연결하기", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))]))),
                const SizedBox(height: 10),
                SizedBox(height: 35, width: 220, child: _hrSpots.isNotEmpty ? LineChart(LineChartData(minY: 40, maxY: 200, gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots, isCurved: true, barWidth: 1.5, color: Colors.cyanAccent, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)))])) : const SizedBox()),
                const Spacer(),
                Container(margin: const EdgeInsets.symmetric(horizontal: 25), padding: const EdgeInsets.all(25), decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), color: Colors.black.withOpacity(0.6), border: Border.all(color: Colors.white24)), child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_dataItem(Icons.favorite, "현재 심박수", _isWatchConnected ? "$_heartRate" : "--", Colors.cyanAccent), _dataItem(Icons.analytics, "평균 심박수", "$_avgHeartRate", Colors.redAccent)]),
                  const SizedBox(height: 30),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_dataItem(Icons.local_fire_department, "칼로리 소모", _calories.toStringAsFixed(1), Colors.orangeAccent), _dataItem(Icons.timer, "운동 시간", _formatDuration(_duration), Colors.blueAccent)]),
                ])),
                const SizedBox(height: 30),
                Padding(padding: const EdgeInsets.only(bottom: 40), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작/중지", _toggleWorkout),
                  _actionBtn(Icons.refresh, "리셋", _resetWorkout),
                  _actionBtn(Icons.file_upload_outlined, "기록저장", _saveRecord),
                  _actionBtn(Icons.bar_chart, "기록보기", () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(records: _records, hrSpots: _hrSpots)));
                    setState(() {}); // 통계 업데이트를 위해 다시 빌드
                  }),
                ])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataItem(IconData i, String l, String v, Color c) => Column(children: [Row(children: [Icon(i, size: 14, color: c), const SizedBox(width: 5), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]), Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold))]);
  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white24)), child: Icon(i, size: 22, color: Colors.white))), const SizedBox(height: 8), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final List<FlSpot> hrSpots;
  const HistoryScreen({Key? key, required this.records, required this.hrSpots}) : super(key: key);
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  void _deleteRecord(int index) async {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("기록 삭제", style: TextStyle(fontSize: 16)), content: const Text("이 운동 기록을 삭제하시겠습니까?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
        TextButton(onPressed: () async {
          setState(() { widget.records.removeAt(index); });
          final prefs = await SharedPreferences.getInstance();
          final List<Map<String, dynamic>> recordList = widget.records.map((r) => {
            'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds,
          }).toList();
          await prefs.setString('workout_records', jsonEncode(recordList));
          Navigator.pop(context);
        }, child: const Text("삭제", style: TextStyle(color: Colors.redAccent))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    // 통계 계산: 최근 7개 기록 합산
    int totalMinutes = widget.records.take(7).fold(0, (sum, r) => sum + r.duration.inMinutes);
    int totalCalories = widget.records.take(7).fold(0, (sum, r) => sum + r.calories.toInt());

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("운동 리포트", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent, elevation: 0),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 통계 섹션 추가
            Container(
              margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.05), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.cyanAccent.withOpacity(0.2))),
              child: Column(children: [
                const Align(alignment: Alignment.centerLeft, child: Text("최근 7회 통계", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13))),
                const SizedBox(height: 15),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _statItem("총 운동 시간", "$totalMinutes분", Icons.timer),
                  _statItem("총 소모 칼로리", "${totalCalories}kcal", Icons.local_fire_department),
                ]),
              ]),
            ),
            // 실시간 그래프 카드
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white10)),
              child: Column(children: [
                const Align(alignment: Alignment.centerLeft, child: Text("실시간 심박수 변화", style: TextStyle(color: Colors.white60, fontSize: 12))),
                const SizedBox(height: 10),
                SizedBox(height: 100, child: LineChart(LineChartData(minY: 40, maxY: 200, gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: widget.hrSpots.isNotEmpty ? widget.hrSpots : [const FlSpot(0, 0)], isCurved: true, color: Colors.cyanAccent, barWidth: 2, dotData: const FlDotData(show: false))]))),
              ]),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 25, vertical: 15), child: Align(alignment: Alignment.centerLeft, child: Text("전체 운동 히스토리", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
            ListView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: widget.records.length,
              itemBuilder: (context, index) {
                final r = widget.records[index];
                return GestureDetector(
                  onLongPress: () => _deleteRecord(index),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
                    child: Row(children: [
                      const Icon(Icons.directions_bike, color: Colors.cyanAccent, size: 18),
                      const SizedBox(width: 15),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.date, style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)), Text("${r.duration.inMinutes}분 운동 완료", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))])),
                      Text("${r.avgHR} BPM", style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) => Column(children: [
    Icon(icon, color: Colors.cyanAccent, size: 18),
    const SizedBox(height: 5),
    Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
    Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
  ]);
}
