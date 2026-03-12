import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  
  await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
  
  FlutterNativeSplash.remove();
  runApp(const BikeFitApp());
}

class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds};
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0, _avgHeartRate = 0;
  double _calories = 0.0, _goalCalories = 150.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false, _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 150.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(item['id'] ?? DateTime.now().toString(), item['date'], item['avgHR'], (item['calories'] as num).toDouble(), Duration(seconds: item['durationSeconds'] ?? 0))).toList();
      }
    });
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // ✅ 배경 이미지 강제 로드
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Indoor bike fit', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                Icon(_isWatchConnected ? Icons.watch : Icons.watch_off, color: Colors.greenAccent)
              ]),
              const Spacer(),
              // ✅ 중앙 자전거 아이콘 (1번 사진의 핵심 UI)
              Image.asset('assets/icon/bike_ui_dark.png', height: 220, errorBuilder: (c, e, s) => const Icon(Icons.directions_bike, size: 100, color: Colors.greenAccent)),
              const Spacer(),
              // ✅ 하단 데이터 박스 (반투명 블랙)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(20)),
                child: Column(children: [
                  LinearProgressIndicator(value: progress, color: Colors.blueAccent, backgroundColor: Colors.white12, minHeight: 10),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _stat("심박수", "$_heartRate", Colors.greenAccent),
                    _stat("평균", "$_avgHeartRate", Colors.redAccent),
                    _stat("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                    _stat("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
                  ]),
                ]),
              ),
              const SizedBox(height: 30),
              // ✅ 하단 제어 버튼
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _iconBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "START", Colors.greenAccent, () {
                  setState(() { _isWorkingOut = !_isWorkingOut; if (_isWorkingOut) { _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) { setState(() { _duration += const Duration(seconds: 1); if (_heartRate >= 95) _calories += 0.15; }); }); } else { _workoutTimer?.cancel(); } });
                }),
                _iconBtn(Icons.save, "SAVE", Colors.white70, () async {
                  if (_isWorkingOut) return;
                  final r = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
                  setState(() { _records.insert(0, r); });
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('workout_records', jsonEncode(_records.map((e) => e.toJson()).toList()));
                  _showToast("저장 완료");
                }),
                _iconBtn(Icons.calendar_month, "REPORT", Colors.white70, () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records)))),
              ]),
              const SizedBox(height: 10),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stat(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 12, color: Colors.white60)), Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c))]);
  Widget _iconBtn(IconData i, String l, Color c, VoidCallback t) => Column(children: [ElevatedButton(onPressed: t, style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(15), backgroundColor: Colors.white10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), side: BorderSide(color: c.withOpacity(0.5))), child: Icon(i, size: 30, color: c)), const SizedBox(height: 5), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60))]);
}

class HistoryScreen extends StatelessWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("기록 리포트")), body: ListView.builder(itemCount: records.length, itemBuilder: (c, i) => ListTile(title: Text("${records[i].date} - ${records[i].calories.toInt()} kcal"), subtitle: Text("${records[i].duration.inMinutes}분 운동"))));
  }
}
