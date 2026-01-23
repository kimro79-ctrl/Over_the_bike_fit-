import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

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
  List<FlSpot> _hrSpots = [const FlSpot(0, 0)];
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
          item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']),
        )).toList();
      });
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
          if (_hrSpots.length > 60) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
          
          // 🔥 심박수 100 이상일 때만 칼로리 계산
          if (_heartRate >= 100) {
            _calories += (_heartRate * 0.012 * (1/60));
          }
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

  void _resetWorkout() {
    if (_isWorkingOut) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동을 먼저 중지해주세요."), duration: Duration(seconds: 1)));
      return;
    }
    setState(() {
      _duration = Duration.zero; _calories = 0.0; _avgHeartRate = 0; _hrSpots = [const FlSpot(0, 0)]; _timeCounter = 0;
    });
    HapticFeedback.mediumImpact();
  }

  void _saveRecord() async {
    if (_duration == Duration.zero) return;
    String date = DateFormat('M/d(E)', 'ko_KR').format(DateTime.now());
    setState(() { _records.insert(0, WorkoutRecord(date, _avgHeartRate, _calories, _duration)); });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(_records.map((r) => {'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds}).toList()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록이 저장되었습니다!")));
  }

  Future<void> _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    showModalBottomSheet(context: context, builder: (c) => StreamBuilder<List<ScanResult>>(
      stream: FlutterBluePlus.scanResults,
      builder: (c, s) {
        final res = (s.data ?? []).where((r) => r.device.platformName.isNotEmpty).toList();
        return ListView.builder(itemCount: res.length, itemBuilder: (c, i) => ListTile(title: Text(res[i].device.platformName), onTap: () async {
          await res[i].device.connect(); _setupDevice(res[i].device); Navigator.pop(context);
        }));
      },
    ));
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() { _isWatchConnected = true; });
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) { if (s.uuid == Guid("180D")) { for (var c in s.characteristics) { if (c.uuid == Guid("2A37")) { await c.setNotifyValue(true); c.lastValueStream.listen(_decodeHR); } } } }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.5, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container()))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('오버 더 바이크 핏', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                const SizedBox(height: 10),
                _smallRoundedBtn(_isWatchConnected ? "워치 연결됨" : "워치 연결하기", _isWatchConnected ? Colors.cyanAccent : Colors.white, _connectWatch),
                
                // 📈 실시간 그래프 (워치 아래 작고 길게)
                Container(
                  height: 45,
                  margin: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                  child: LineChart(LineChartData(
                    gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
                    lineBarsData: [LineChartBarData(spots: _hrSpots, isCurved: true, color: Colors.cyanAccent, barWidth: 1.5, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)))],
                  )),
                ),

                const Spacer(),
                
                // 📊 일간 데이터 배너 (1/2 크기 축소)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 30),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _compactStat("현재심박", "$_heartRate", Colors.cyanAccent),
                      _compactStat("평균심박", "$_avgHeartRate", Colors.redAccent),
                      _compactStat("칼로리", _calories.toStringAsFixed(0), Colors.orangeAccent),
                      _compactStat("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
                    ],
                  ),
                ),

                const Spacer(),

                // 🔘 하단 버튼 (둥근 사각형 + 작게)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _rectBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작/정지", _toggleWorkout),
                      const SizedBox(width: 15),
                      _rectBtn(Icons.refresh, "리셋", _resetWorkout),
                      const SizedBox(width: 15),
                      _rectBtn(Icons.save, "저장", _saveRecord),
                      const SizedBox(width: 15),
                      _rectBtn(Icons.bar_chart, "기록보기", () {
                        Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, hrSpots: _hrSpots)));
                      }),
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

  Widget _smallRoundedBtn(String t, Color c, VoidCallback tap) => GestureDetector(onTap: tap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withOpacity(0.5))), child: Text(t, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold))));
  Widget _compactStat(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 9, color: Colors.white54)), Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c))]);
  Widget _rectBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white12)), child: Icon(i, color: Colors.white, size: 22))), const SizedBox(height: 5), Text(l, style: const TextStyle(fontSize: 9, color: Colors.white70))]);
}

class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final List<FlSpot> hrSpots;
  const HistoryScreen({Key? key, required this.records, required this.hrSpots}) : super(key: key);
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    DateTime now = DateTime.now();
    int daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    Set<int> workoutDays = widget.records.map((r) {
      try { return int.parse(r.date.split('/')[1].split('(')[0]); } catch (e) { return -1; }
    }).toSet();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("운동 리포트", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        child: Column(children: [
          // 📅 달력 섹션
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
            child: GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
              itemCount: daysInMonth,
              itemBuilder: (c, i) {
                int day = i + 1;
                bool isDone = workoutDays.contains(day);
                return Column(children: [
                  Text("$day", style: TextStyle(fontSize: 11, color: isDone ? Colors.cyanAccent : Colors.white24)),
                  if (isDone) Container(margin: const EdgeInsets.only(top: 2), width: 4, height: 4, decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle)),
                ]);
              },
            ),
          ),
          // 리스트 섹션
          ListView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.records.length,
            itemBuilder: (c, i) {
              final r = widget.records[i];
              return ListTile(
                leading: const Icon(Icons.directions_bike, color: Colors.cyanAccent),
                title: Text("${r.duration.inMinutes}분 운동 (${r.avgHR} BPM)"),
                subtitle: Text(r.date),
                trailing: Text("${r.calories.toInt()} kcal", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                onLongPress: () { /* 삭제 로직 생략(공간상) */ },
              );
            },
          ),
        ]),
      ),
    );
  }
}
