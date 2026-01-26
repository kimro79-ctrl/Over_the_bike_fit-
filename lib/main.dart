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

class WorkoutRecord {
  final String id;
  final String date;
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

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0, _avgHeartRate = 0;
  double _calories = 0.0, _goalCalories = 300.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false, _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];

  @override
  void initState() { super.initState(); _loadInitialData(); }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(item['id'] ?? DateTime.now().toString(), item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']))).toList();
      }
    });
  }

  // ✅ 작고 심플한 칼로리 설정 팝업
  void _showGoalSettings() {
    final controller = TextEditingController(text: _goalCalories.toInt().toString());
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          height: 220, 
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 35, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              const Text("목표 칼로리 설정", style: TextStyle(fontSize: 15, color: Colors.white70)),
              const Spacer(),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF5FFBBA), fontSize: 28, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    suffixText: "kcal", 
                    suffixStyle: TextStyle(fontSize: 14, color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5FFBBA))),
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5FFBBA),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14)
                  ),
                  onPressed: () async {
                    setState(() { _goalCalories = double.tryParse(controller.text) ?? 300.0; });
                    (await SharedPreferences.getInstance()).setDouble('goal_calories', _goalCalories);
                    Navigator.pop(context);
                  },
                  child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 메인 UI 영역 (절대 보존) ---
  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            _connectButton(),
          ]),
          const SizedBox(height: 25),
          _chartArea(),
          const Spacer(),
          GestureDetector(onTap: _showGoalSettings, child: _goalProgressView(progress)),
          const SizedBox(height: 20),
          _dataBanner(),
          const SizedBox(height: 30),
          _controlButtons(),
          const SizedBox(height: 40),
        ]))),
      ]),
    );
  }

  Widget _connectButton() => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.greenAccent)), child: const Text("연결됨", style: TextStyle(color: Colors.greenAccent, fontSize: 10)));
  Widget _chartArea() => SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])));
  Widget _goalProgressView(double p) => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CALORIE GOAL", style: TextStyle(fontSize: 11, color: Colors.white70)), Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(fontSize: 12, color: Colors.greenAccent))]), const SizedBox(height: 10), ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: p, backgroundColor: Colors.white12, color: Colors.greenAccent, minHeight: 8))]));
  Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.greenAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);
  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionBtn(Icons.play_arrow, "시작", () {}), const SizedBox(width: 15),
    _actionBtn(Icons.refresh, "리셋", () {}), const SizedBox(width: 15),
    _actionBtn(Icons.save, "저장", () {}), const SizedBox(width: 15),
    _actionBtn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records)))),
  ]);
  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), child: Icon(i, size: 24, color: Colors.white))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
}

// --- 히스토리 리포트 화면 (버튼별 그래프 전환 적용) ---
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  double _weight = 70.0;
  int _chartPeriod = 7; // 기본 주간 설정

  @override
  void initState() { super.initState(); _loadWeight(); }
  Future<void> _loadWeight() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _weight = prefs.getDouble('last_weight') ?? 70.0; });
  }

  double _getSum(int days) {
    final limit = DateTime.now().subtract(Duration(days: days));
    return widget.records.where((r) => DateTime.parse(r.date).isAfter(limit)).fold(0.0, (sum, r) => sum + r.calories);
  }

  List<BarChartGroupData> _getChartData(int days) {
    final limit = DateTime.now().subtract(Duration(days: days));
    var filtered = widget.records.where((r) => DateTime.parse(r.date).isAfter(limit)).toList();
    filtered = filtered.reversed.toList();
    return List.generate(filtered.length, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: filtered[i].calories, color: const Color(0xFF4285F4), width: 15, borderRadius: BorderRadius.circular(4))]));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(title: const Text("기록 리포트", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
        body: SingleChildScrollView(child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            _weightBar(),
            const SizedBox(height: 12),
            Row(children: [
              _dataBar("주간 합계", "${_getSum(7).toInt()} kcal", const Color(0xFF4285F4)),
              const SizedBox(width: 10),
              _dataBar("월간 합계", "${_getSum(30).toInt()} kcal", const Color(0xFF3F51B5)),
            ]),
          ])),
          
          // ✅ 일간, 주간, 월간 버튼
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            _periodBtn("일간", 1), const SizedBox(width: 8),
            _periodBtn("주간", 7), const SizedBox(width: 8),
            _periodBtn("월간", 30),
          ])),

          // ✅ 누르면 바뀌는 칼로리 그래프
          Container(
            height: 180, margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
            child: BarChart(BarChartData(
              barGroups: _getChartData(_chartPeriod),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
            )),
          ),

          // ✅ 달력 섹션 (스팟 표시)
          _calendarSection(),
        ])),
      ),
    );
  }

  Widget _weightBar() => Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), decoration: BoxDecoration(color: const Color(0xFF678392), borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("나의 현재 체중", style: TextStyle(color: Colors.white70, fontSize: 16)), Text("${_weight}kg", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))]));
  Widget _dataBar(String l, String v, Color c) => Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)), const Icon(Icons.bar_chart, color: Colors.white54, size: 16)]), const SizedBox(height: 8), Text(v, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))])));
  
  Widget _periodBtn(String label, int days) {
    bool isSel = _chartPeriod == days;
    return Expanded(child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: isSel ? const Color(0xFF4285F4) : Colors.white, foregroundColor: isSel ? Colors.white : Colors.black54, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      onPressed: () => setState(() => _chartPeriod = days),
      child: Text(label),
    ));
  }

  Widget _calendarSection() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), padding: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
    child: TableCalendar(
      locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay, rowHeight: 45,
      headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
      eventLoader: (day) => widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(day)).toList(),
      calendarStyle: const CalendarStyle(markerDecoration: BoxDecoration(color: Color(0xFF9FA8DA), shape: BoxShape.circle), selectedDecoration: BoxDecoration(color: Color(0xFF4285F4), shape: BoxShape.circle)),
    ),
  );
}
