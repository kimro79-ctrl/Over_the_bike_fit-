import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart'; // 캘린더 패키지 사용

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
      home: const SplashScreen(),
    );
  }
}

// -------------------------------------------------------------------------
// 1. 스플래쉬 화면 (3초 유지)
// -------------------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WorkoutScreen()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/splash/splash_screen.png', width: 200, errorBuilder: (c, e, s) => const Icon(Icons.flash_on, size: 100)),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: Colors.cyanAccent),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// 2. 메인 운동 화면 (시뮬레이션 제거 + 로고 하단 그래프)
// -------------------------------------------------------------------------
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0; // 실제 워치 수신 데이터용
  List<FlSpot> _hrSpots = []; 
  double _timeX = 0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false;

  // 시뮬레이션 삭제됨: 실제 데이터가 들어올 때 이 함수를 호출하세요.
  void updateHeartRate(int newRate) {
    if (!_isWorkingOut) return;
    setState(() {
      _heartRate = newRate;
      _hrSpots.add(FlSpot(_timeX, _heartRate.toDouble()));
      _timeX += 1.0; 
      if (_hrSpots.length > 50) _hrSpots.removeAt(0); // 최근 데이터만 유지
    });
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _duration += const Duration(seconds: 1));
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _resetWorkout() {
    _workoutTimer?.cancel();
    setState(() {
      _isWorkingOut = false;
      _duration = Duration.zero;
      _heartRate = 0;
      _hrSpots.clear();
      _timeX = 0;
    });
  }

  Future<void> _saveRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> records = prefs.getStringList('workout_records') ?? [];
    
    Map<String, dynamic> newRecord = {
      'date': DateTime.now().toIso8601String(),
      'duration': _duration.inSeconds,
      'avgHr': _hrSpots.isEmpty ? 0 : (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt(),
      'kcal': (_duration.inSeconds * 0.15).toStringAsFixed(1),
    };
    
    records.add(jsonEncode(newRecord));
    await prefs.setStringList('workout_records', records);
    _resetWorkout();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록이 저장되었습니다!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(15.0),
              child: Text("Indoor Bike Fit", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            
            // 인도어 바이크 로고
            Expanded(
              flex: 2,
              child: Image.asset('assets/icon/bike_ui_dark.png', fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Icon(Icons.directions_bike, size: 80)),
            ),

            // 실시간 그래프 (로고 밑, 크기 축소)
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: LineChart(
                  LineChartData(
                    minY: 40, maxY: 200,
                    gridData: FlGridData(show: false),
                    titlesData: FlTitlesData(show: false),
                    borderData: FlBorderData(show: true, border: Border.all(color: Colors.white10)),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _hrSpots,
                        isCurved: true,
                        color: Colors.cyanAccent,
                        barWidth: 3,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)),
                      )
                    ],
                  ),
                ),
              ),
            ),

            // 데이터 바
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statItem("심박수", "$_heartRate", Colors.greenAccent),
                  _statItem("칼로리", (_duration.inSeconds * 0.15).toStringAsFixed(1), Colors.orangeAccent),
                  _statItem("시간", _formatDuration(_duration), Colors.blueAccent),
                ],
              ),
            ),

            // 하단 버튼
            Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _circleBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", _toggleWorkout, Colors.white12),
                  _circleBtn(Icons.refresh, "리셋", _resetWorkout, Colors.white12),
                  _circleBtn(Icons.save, "저장", _saveRecord, Colors.white12),
                  _circleBtn(Icons.calendar_month, "기록", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const CalendarPage()));
                  }, Colors.cyanAccent.withOpacity(0.2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String l, String v, Color c) => Column(children: [
    Text(l, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    Text(v, style: TextStyle(color: c, fontSize: 24, fontWeight: FontWeight.bold))
  ]);

  Widget _circleBtn(IconData i, String l, VoidCallback t, Color b) => Column(children: [
    GestureDetector(onTap: t, child: CircleAvatar(radius: 28, backgroundColor: b, child: Icon(i, color: Colors.white))),
    const SizedBox(height: 5),
    Text(l, style: const TextStyle(fontSize: 11))
  ]);

  String _formatDuration(Duration d) => "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

// -------------------------------------------------------------------------
// 3. 캘린더 페이지 (TableCalendar 적용)
// -------------------------------------------------------------------------
class CalendarPage extends StatefulWidget {
  const CalendarPage({Key? key}) : super(key: key);
  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<dynamic>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> records = prefs.getStringList('workout_records') ?? [];
    Map<DateTime, List<dynamic>> tempEvents = {};
    for (var r in records) {
      var decoded = jsonDecode(r);
      DateTime date = DateTime.parse(decoded['date']);
      DateTime day = DateTime(date.year, date.month, date.day);
      if (tempEvents[day] == null) tempEvents[day] = [];
      tempEvents[day]!.add(decoded);
    }
    setState(() => _events = tempEvents);
  }

  @override
  Widget build(BuildContext context) {
    final selectedRecords = _events[DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day)] ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록"), backgroundColor: Colors.black),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            eventLoader: (day) => _events[DateTime(day.year, day.month, day.day)] ?? [],
            calendarStyle: const CalendarStyle(
              selectedDecoration: BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle),
              selectedTextStyle: TextStyle(color: Colors.black),
              todayDecoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
            ),
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: ListView.builder(
              itemCount: selectedRecords.length,
              itemBuilder: (context, i) {
                final r = selectedRecords[i];
                return ListTile(
                  leading: const Icon(Icons.flash_on, color: Colors.orangeAccent),
                  title: Text("${r['kcal']} kcal 소모"),
                  subtitle: Text("시간: ${r['duration']}초 | 평균 심박수: ${r['avgHr']} bpm"),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
