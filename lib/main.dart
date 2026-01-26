import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
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

// 운동 기록 데이터 모델
class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds
  };
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
  int _heartRate = 0;
  double _calories = 0.0;
  List<WorkoutRecord> _records = [];

  @override
  void initState() { super.initState(); _loadInitialData(); }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(item['id'] ?? DateTime.now().toString(), item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']))).toList();
      }
    });
  }

  Future<void> _updateRecords(List<WorkoutRecord> newRecords) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(newRecords.map((r) => r.toJson()).toList());
    await prefs.setString('workout_records', encoded);
    setState(() { _records = newRecords; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        // 1. 메인 배경 이미지 (기존 디자인 복구)
        Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black))),
        Positioned.fill(child: Container(color: Colors.black.withOpacity(0.4))),
        
        SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          const SizedBox(height: 60),
          const Text('Indoor bike fit', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5)),
          const Spacer(),
          
          // 2. 데이터 대시보드
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white10)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _statItem("심박수", "$_heartRate", Colors.greenAccent),
              _statItem("칼로리", "${_calories.toInt()}", Colors.orangeAccent),
              _statItem("시간", "00:00", Colors.blueAccent),
            ]),
          ),
          
          const SizedBox(height: 40),
          
          // 3. 기록 이동 버튼
          Column(children: [
            GestureDetector(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onUpdate: _updateRecords)));
                _loadInitialData();
              },
              child: Container(width: 70, height: 70, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white24)), child: const Icon(Icons.calendar_month, size: 32, color: Colors.white)),
            ),
            const SizedBox(height: 12),
            const Text("운동 기록", style: TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500))
          ]),
          const SizedBox(height: 60),
        ]))),
      ]),
    );
  }

  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 12, color: Colors.white54)), const SizedBox(height: 10), Text(v, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c))]);
}

// --- 히스토리 리포트 화면 ---
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final Function(List<WorkoutRecord>) onUpdate;
  const HistoryScreen({Key? key, required this.records, required this.onUpdate}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  double _weight = 70.0;
  late List<WorkoutRecord> _currentRecords;

  @override
  void initState() { super.initState(); _currentRecords = List.from(widget.records); _selectedDay = _focusedDay; _loadWeight(); }

  Future<void> _loadWeight() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _weight = prefs.getDouble('last_weight') ?? 70.0; });
  }

  // 체중 설정 다이얼로그
  void _showWeightSetting() {
    final controller = TextEditingController(text: _weight.toString());
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text("체중 설정"),
      content: TextField(controller: controller, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(suffixText: "kg", enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)))),
      actions: [TextButton(onPressed: () async {
        final nw = double.tryParse(controller.text) ?? 70.0;
        (await SharedPreferences.getInstance()).setDouble('last_weight', nw);
        setState(() => _weight = nw); Navigator.pop(context);
      }, child: const Text("확인"))],
    ));
  }

  // 기간별 그래프 팝업
  void _showGraphPopup(String title, int days, Color color) {
    final limit = DateTime.now().subtract(Duration(days: days));
    var filtered = _currentRecords.where((r) => DateTime.parse(r.date).isAfter(limit)).toList().reversed.toList();
    showModalBottomSheet(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))), builder: (context) => Container(
      height: 380, padding: const EdgeInsets.all(30),
      child: Column(children: [
        Text("$title 칼로리 통계", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 35),
        Expanded(child: BarChart(BarChartData(
          barGroups: List.generate(filtered.length, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: filtered[i].calories, color: color, width: 18, borderRadius: BorderRadius.circular(6))])),
          borderData: FlBorderData(show: false), titlesData: const FlTitlesData(show: false), gridData: const FlGridData(show: false),
        ))),
      ]),
    ));
  }

  // 삭제 확인 다이얼로그
  void _confirmDelete(String id) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text("기록 삭제"),
      content: const Text("정말로 이 기록을 삭제하시겠습니까?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
        TextButton(onPressed: () { setState(() { _currentRecords.removeWhere((r) => r.id == id); widget.onUpdate(_currentRecords); }); Navigator.pop(context); }, child: const Text("삭제", style: TextStyle(color: Colors.redAccent))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dailyRecords = _currentRecords.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();

    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(title: const Text("운동 리포트", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
        body: SingleChildScrollView(child: Column(children: [
          // 1. 체중 바 (클릭 시 설정)
          GestureDetector(onTap: _showWeightSetting, child: Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20), decoration: BoxDecoration(color: const Color(0xFF4A6572), borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("나의 현재 체중", style: TextStyle(color: Colors.white, fontSize: 16)), Text("${_weight}kg", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22))]))),
          
          // 2. 일/주/월 버튼 (색상 분할)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            _colorBtn("일간", Colors.redAccent.shade200, () => _showGraphPopup("일간", 1, Colors.redAccent)),
            const SizedBox(width: 10),
            _colorBtn("주간", Colors.orangeAccent.shade200, () => _showGraphPopup("주간", 7, Colors.orangeAccent)),
            const SizedBox(width: 10),
            _colorBtn("월간", Colors.blueAccent.shade200, () => _showGraphPopup("월간", 30, Colors.blueAccent)),
          ])),

          // 3. 달력 (기록 스팟 포함)
          Container(margin: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)]), child: TableCalendar(
            locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            eventLoader: (day) => _currentRecords.where((r) => r.date == DateFormat('yyyy-MM-dd').format(day)).toList(),
            calendarStyle: const CalendarStyle(markerDecoration: BoxDecoration(color: Color(0xFF9FA8DA), shape: BoxShape.circle), selectedDecoration: BoxDecoration(color: Color(0xFF4285F4), shape: BoxShape.circle)),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
          )),

          // 4. 상세 목록 (길게 눌러 삭제)
          const Padding(padding: EdgeInsets.only(left: 20, bottom: 10), child: Align(alignment: Alignment.centerLeft, child: Text("기록 리스트 (길게 눌러 삭제)", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)))),
          ListView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: dailyRecords.length,
            itemBuilder: (context, index) {
              final r = dailyRecords[index];
              return Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200)), child: ListTile(
                onLongPress: () => _confirmDelete(r.id),
                leading: CircleAvatar(backgroundColor: Colors.blue.shade50, child: const Icon(Icons.directions_bike, color: Color(0xFF4285F4), size: 20)),
                title: Text("${r.calories.toInt()} kcal", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${r.avgHR} bpm / ${r.duration.inMinutes}분"),
                trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: () => _confirmDelete(r.id)),
              ));
            },
          ),
          const SizedBox(height: 40),
        ])),
      ),
    );
  }

  Widget _colorBtn(String label, Color color, VoidCallback onTap) => Expanded(child: ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.symmetric(vertical: 15)),
    onPressed: onTap, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
  ));
}
