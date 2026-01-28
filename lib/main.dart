// 1. 모든 import 구문은 반드시 파일 최상단에 위치해야 합니다.
import 'dart:async'; // Timer, StreamSubscription 필수 라이브러리
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
  int _heartRate = 0, _avgHeartRate = 0;
  double _calories = 0.0, _goalCalories = 300.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer; // dart:async 필요
  bool _isWorkingOut = false, _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];
  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription; // dart:async 필요

  @override
  void initState() { super.initState(); _loadInitialData(); }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(
          item['id'] ?? DateTime.now().toString(), 
          item['date'], 
          item['avgHR'], 
          (item['calories'] as num).toDouble(),
          Duration(seconds: item['durationSeconds'] ?? 0)
        )).toList();
      }
    });
  }

  // 블루투스 스캔 팝업
  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _filteredResults.clear();

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidScanMode: AndroidScanMode.lowLatency,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context, 
      backgroundColor: const Color(0xFF1E1E1E), 
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), 
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) { 
          if (mounted) setModalState(() { _filteredResults = results; }); 
        });
        return Container(padding: const EdgeInsets.all(20), height: MediaQuery.of(context).size.height * 0.4, child: Column(children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text("근처 워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          Expanded(child: ListView.builder(itemCount: _filteredResults.length, itemBuilder: (context, index) {
            final d = _filteredResults[index].device;
            final name = d.platformName.isEmpty ? "기기 (${d.remoteId})" : d.platformName;
            return ListTile(
              leading: const Icon(Icons.watch, color: Colors.blueAccent), 
              title: Text(name, style: const TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(context); _connectToDevice(d); }
            );
          })) 
        ]));
      })).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });
  }

  void _connectToDevice(BluetoothDevice device) async { try { await device.connect(); _setupDevice(device); } catch (e) { _showToast("연결 실패"); } }
  
  void _setupDevice(BluetoothDevice device) async { 
    setState(() { _isWatchConnected = true; }); 
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) { 
      if (s.uuid == Guid("180D")) { 
        for (var c in s.characteristics) { 
          if (c.uuid == Guid("2A37")) { 
            await c.setNotifyValue(true);
            c.lastValueStream.listen(_decodeHR); 
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
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
        }
      });
    }
  }

  void _showGoalSettings() {
    final controller = TextEditingController(text: _goalCalories.toInt().toString());
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1E1E1E), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(padding: const EdgeInsets.all(25), height: 260, child: Column(children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 25),
          const Text("목표 칼로리 설정", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 20),
          TextField(controller: controller, keyboardType: TextInputType.number, autofocus: true, textAlign: TextAlign.center, style: const TextStyle(color: Colors.blueAccent, fontSize: 36, fontWeight: FontWeight.bold), decoration: const InputDecoration(suffixText: "kcal", suffixStyle: TextStyle(color: Colors.white38, fontSize: 16))),
          const Spacer(),
          SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: () async {
            setState(() { _goalCalories = double.tryParse(controller.text) ?? 300.0; });
            (await SharedPreferences.getInstance()).setDouble('goal_calories', _goalCalories);
            Navigator.pop(context);
          }, child: const Text("설정 완료", style: TextStyle(fontWeight: FontWeight.bold)))),
        ])),
      ),
    );
  }

  void _showToast(String msg) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1))); }

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            const SizedBox(height: 40),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              _connectButton(),
            ]),
            const SizedBox(height: 30),
            _chartArea(),
            const SizedBox(height: 100),
            GestureDetector(onTap: _showGoalSettings, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)), child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("CALORIE GOAL", style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(5), child: SizedBox(height: 10, child: LinearProgressIndicator(value: progress, backgroundColor: Colors.white12, color: Colors.blueAccent))),
            ]))),
            const SizedBox(height: 20),
            _dataBanner(),
            const SizedBox(height: 30),
            _controlButtons(),
          ]),
        ),
      ),
    );
  }

  Widget _connectButton() => GestureDetector(onTap: _showDeviceScanPopup, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: _isWatchConnected ? Colors.blueAccent : Colors.white38)), child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: TextStyle(color: _isWatchConnected ? Colors.blueAccent : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))));
  Widget _chartArea() => SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.blueAccent, barWidth: 3, dotData: const FlDotData(show: false))])));
  Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.blueAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.white)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);
  
  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", () { 
      setState(() { 
        _isWorkingOut = !_isWorkingOut; 
        if (_isWorkingOut) { 
          _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
            setState(() { _duration += const Duration(seconds: 1); if (_heartRate >= 95) { _calories += 0.15; } }); 
          }); 
        } else { _workoutTimer?.cancel(); } 
      }); 
    }),
    const SizedBox(width: 15),
    _actionBtn(Icons.refresh, "리셋", () { 
      if(!_isWorkingOut) { setState((){ _duration=Duration.zero; _calories=0.0; _avgHeartRate=0; _heartRate=0; _hrSpots=[]; _timeCounter=0; }); _showToast("리셋되었습니다."); } 
    }),
    const SizedBox(width: 15),
    _actionBtn(Icons.save, "저장", () async {
      if (_isWorkingOut) { _showToast("일시정지 후 저장하세요."); return; }
      if (_duration.inSeconds < 5) return;
      final newRec = WorkoutRecord(DateTime.now().millisecondsSinceEpoch.toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
      setState(() { _records.insert(0, newRec); });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_records', jsonEncode(_records.map((r) => r.toJson()).toList()));
      _showToast("저장 완료!");
    }),
    const SizedBox(width: 15),
    _actionBtn(Icons.calendar_month, "기록", () async {
      await Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records)));
      _loadInitialData();
    }),
  ]);
  
  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white, size: 24))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
}

class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late List<WorkoutRecord> _currentRecords;

  @override
  void initState() { 
    super.initState(); 
    _currentRecords = List.from(widget.records); 
    _selectedDay = _focusedDay; 
  }

  // 데이터 시각화 팝업
  void _showGraphPopup() {
    final limit = DateTime.now().subtract(const Duration(days: 7));
    var filtered = _currentRecords.where((r) => DateTime.parse(r.date).isAfter(limit)).toList();
    if (filtered.isEmpty) return;

    double maxCal = filtered.map((e) => e.calories).reduce((a, b) => a > b ? a : b);
    
    showModalBottomSheet(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), 
      builder: (context) => Container(height: 350, padding: const EdgeInsets.all(25), child: Column(children: [
        const Text("최근 7일 칼로리 소모", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 30),
        Expanded(child: BarChart(BarChartData(
          maxY: maxCal * 1.3,
          barGroups: List.generate(filtered.length, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: filtered[i].calories, color: Colors.blueAccent, width: 18, borderRadius: BorderRadius.circular(4))])),
          // ✅ 로그에서 지적된 에러 해결: 구버전 문법 tooltipBgColor 사용
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: Colors.blueAccent.withOpacity(0.9),
            ),
          ),
          gridData: const FlGridData(show: false), 
          titlesData: const FlTitlesData(show: false), 
          borderData: FlBorderData(show: false), 
        ))),
      ]))
    );
  }

  @override
  Widget build(BuildContext context) {
    final dailyRecords = _currentRecords.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        appBar: AppBar(
          title: const Text("기록 리포트"),
          actions: [IconButton(icon: const Icon(Icons.bar_chart), onPressed: _showGraphPopup)],
        ),
        body: SingleChildScrollView(child: Column(children: [
          TableCalendar(
            locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            calendarStyle: const CalendarStyle(todayDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
          ),
          const Divider(),
          ...dailyRecords.map((r) => ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.directions_bike, color: Colors.white, size: 20)),
            title: Text("${r.calories.toInt()} kcal 소모"), 
            subtitle: Text("${r.duration.inMinutes}분 운동 | 평균 ${r.avgHR} BPM"),
          )).toList()
        ])),
      ),
    );
  }
}
