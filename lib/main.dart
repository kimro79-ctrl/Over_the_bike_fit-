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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  runApp(const BikeFitApp());
}

// --- 데이터 모델 ---
class WorkoutRecord {
  final String id;
  final String date; // yyyy-MM-dd
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
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

// --- 메인 화면 ---
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0;
  int _avgHeartRate = 0;
  double _calories = 0.0;
  double _goalCalories = 300.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(item['id'], item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']))).toList();
      }
    });
  }

  void _showGoalPopup() {
    final controller = TextEditingController(text: _goalCalories.toInt().toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("목표 칼로리 설정"),
        content: TextField(controller: controller, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, color: Colors.greenAccent)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          TextButton(onPressed: () async {
            setState(() { _goalCalories = double.tryParse(controller.text) ?? 300.0; });
            (await SharedPreferences.getInstance()).setDouble('goal_calories', _goalCalories);
            Navigator.pop(context);
          }, child: const Text("저장")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('BIKE FIT', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.greenAccent)),
              _topBtn("워치 연결", _isWatchConnected ? Colors.blue : Colors.white24, () {}),
            ]),
          ),
          const Spacer(),
          // 중앙 심박수 강조
          Text("$_heartRate", style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.white)),
          const Text("CURRENT BPM", style: TextStyle(color: Colors.white24, letterSpacing: 2)),
          const Spacer(),
          
          // 목표 진행 바
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: GestureDetector(
              onTap: _showGoalPopup,
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("CALORIE GOAL", style: TextStyle(fontSize: 10, color: Colors.white54)),
                  Text("${(progress * 100).toInt()}%", style: const TextStyle(fontSize: 10, color: Colors.greenAccent)),
                ]),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress, backgroundColor: Colors.white10, color: Colors.greenAccent, minHeight: 8),
              ]),
            ),
          ),
          const SizedBox(height: 30),
          
          // 데이터 배너
          _dataBanner(),
          const SizedBox(height: 30),
          
          // 조작 버튼 (사각형 강조)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _mainBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, _isWorkingOut ? Colors.orange : Colors.greenAccent, () {
              setState(() {
                _isWorkingOut = !_isWorkingOut;
                if (_isWorkingOut) {
                  _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() {
                    _duration += const Duration(seconds: 1);
                    _calories += 0.15; // 임시 계산식
                  }));
                } else { _workoutTimer?.cancel(); }
              });
            }),
            const SizedBox(width: 20),
            _mainBtn(Icons.save, Colors.blueAccent, () async {
              if (_duration.inSeconds < 5) return;
              final newRecord = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
              setState(() { _records.insert(0, newRecord); });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('workout_records', jsonEncode(_records.map((r) => {'id': r.id, 'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds}).toList()));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록 저장 완료!")));
            }),
            const SizedBox(width: 20),
            _mainBtn(Icons.bar_chart, Colors.purpleAccent, () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records)))),
          ]),
          const SizedBox(height: 50),
        ]),
      ),
    );
  }

  Widget _topBtn(String t, Color c, VoidCallback o) => OutlinedButton(onPressed: o, style: OutlinedButton.styleFrom(side: BorderSide(color: c), foregroundColor: c), child: Text(t, style: const TextStyle(fontSize: 10)));

  Widget _mainBtn(IconData i, Color c, VoidCallback o) => GestureDetector(
    onTap: o,
    child: Container(
      width: 70, height: 70,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: c, width: 2),
        boxShadow: [BoxShadow(color: c.withOpacity(0.3), blurRadius: 10, spreadRadius: 1)]
      ),
      child: Icon(i, color: c, size: 30),
    ),
  );

  Widget _dataBanner() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _stat("AVG HR", "$_avgHeartRate"),
    _stat("KCAL", _calories.toStringAsFixed(1)),
    _stat("TIME", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}"),
  ]);

  Widget _stat(String l, String v) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white30)), Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]);
}

// --- 히스토리 및 통계 화면 ---
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  double _weight = 70.0;

  @override
  void initState() { super.initState(); _loadWeight(); }
  
  void _loadWeight() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _weight = prefs.getDouble('user_weight') ?? 70.0; });
  }

  @override
  Widget build(BuildContext context) {
    // 주간 합계 계산
    double weeklyKcal = widget.records.where((r) => DateTime.parse(r.date).isAfter(DateTime.now().subtract(const Duration(days: 7)))).fold(0, (sum, r) => sum + r.calories);

    return Scaffold(
      appBar: AppBar(title: const Text("REPORT"), backgroundColor: Colors.black),
      body: SingleChildScrollView(
        child: Column(children: [
          // 체중 설정 카드
          _infoCard("체중 설정", "${_weight}kg", Icons.monitor_weight, () => _editWeight()),
          // 주간 통계 카드
          _infoCard("최근 7일 소모량", "${weeklyKcal.toInt()} kcal", Icons.local_fire_department, null),
          
          // 달력 (운동한 날 표시)
          Container(
            margin: const EdgeInsets.all(15),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
            child: TableCalendar(
              firstDay: DateTime(2025), lastDay: DateTime(2030), focusedDay: _focusedDay,
              headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
              calendarStyle: const CalendarStyle(todayDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
              eventLoader: (day) {
                return widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(day)).toList();
              },
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, events) {
                  if (events.isNotEmpty) {
                    return Positioned(bottom: 1, child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)));
                  }
                  return null;
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoCard(String t, String v, IconData i, VoidCallback? o) => GestureDetector(
    onTap: o,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        Icon(i, color: Colors.greenAccent),
        const SizedBox(width: 20),
        Text(t),
        const Spacer(),
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ]),
    ),
  );

  void _editWeight() {
    final controller = TextEditingController(text: _weight.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("체중 입력"),
        content: TextField(controller: controller, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () async {
            setState(() { _weight = double.tryParse(controller.text) ?? 70.0; });
            (await SharedPreferences.getInstance()).setDouble('user_weight', _weight);
            Navigator.pop(context);
          }, child: const Text("저장")),
        ],
      ),
    );
  }
}
