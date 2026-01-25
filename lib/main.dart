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

// --- 모델 클래스 ---
class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
}

class WeightRecord {
  final String date;
  final double weight;
  WeightRecord(this.date, this.weight);
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Indoor bike fit',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
      home: const WorkoutScreen(),
    );
  }
}

// --- 메인 운동 화면 ---
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0;
  int _avgHeartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];
  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

  @override
  void initState() { super.initState(); _loadRecords(); }

  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: true);
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1A1A1A), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (context) => StatefulBuilder(builder: (context, setModalState) {
      _scanSubscription = FlutterBluePlus.onScanResults.listen((results) { if (mounted) setModalState(() { _filteredResults = results.where((r) => r.device.platformName.isNotEmpty).toList(); }); });
      return Container(padding: const EdgeInsets.all(20), height: 400, child: Column(children: [Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))), const SizedBox(height: 20), const Text("워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Expanded(child: _filteredResults.isEmpty ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent)) : ListView.builder(itemCount: _filteredResults.length, itemBuilder: (context, index) => ListTile(leading: const Icon(Icons.bluetooth, color: Colors.blueAccent), title: Text(_filteredResults[index].device.platformName), onTap: () { Navigator.pop(context); _connectToDevice(_filteredResults[index].device); }))) ]));
    })).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });
  }

  void _connectToDevice(BluetoothDevice device) async { try { await device.connect(); _setupDevice(device); } catch (e) { _showToast("연결 실패"); } }
  void _setupDevice(BluetoothDevice device) async { setState(() { _isWatchConnected = true; }); List<BluetoothService> services = await device.discoverServices(); for (var s in services) { if (s.uuid == Guid("180D")) { for (var c in s.characteristics) { if (c.uuid == Guid("2A37")) { await c.setNotifyValue(true); c.lastValueStream.listen(_decodeHR); } } } } }

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

  void _handleSaveRecord() {
    if (_isWorkingOut) { _showToast("운동을 먼저 정지해 주세요."); return; }
    if (_duration.inSeconds < 5) { _showToast("기록하기에 운동 시간이 너무 짧습니다."); return; }
    String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    setState(() { _records.insert(0, WorkoutRecord(DateTime.now().toString(), dateStr, _avgHeartRate, _calories, _duration)); });
    _saveToPrefs(); _showToast("기록이 저장되었습니다.");
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? res = prefs.getString('workout_records');
    if (res != null) {
      final List<dynamic> decoded = jsonDecode(res);
      setState(() { _records = decoded.map((item) => WorkoutRecord(item['id'] ?? DateTime.now().toString(), item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']))).toList(); });
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(_records.map((r) => {'id': r.id, 'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds}).toList()));
  }

  void _showToast(String msg) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1))); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.9, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          const SizedBox(height: 40),
          const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5)),
          const SizedBox(height: 15),
          _connectButton(),
          const SizedBox(height: 25),
          _chartArea(),
          const Spacer(),
          _dataBanner(),
          const SizedBox(height: 30),
          _controlButtons(),
          const SizedBox(height: 40),
        ]))),
      ]),
    );
  }

  Widget _connectButton() => GestureDetector(onTap: _showDeviceScanPopup, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.greenAccent, width: 1.2)), child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold))));
  Widget _chartArea() => SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])));
  Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.greenAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 11, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c))]);
  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [_actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작/정지", () { setState(() { _isWorkingOut = !_isWorkingOut; if (_isWorkingOut) { _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() { _duration += const Duration(seconds: 1); if (_heartRate >= 95) _calories += (95 * 0.012 * (1/60)); })); } else { _workoutTimer?.cancel(); } }); }), const SizedBox(width: 15), _actionBtn(Icons.refresh, "리셋", () { if(!_isWorkingOut) setState((){_duration=Duration.zero;_calories=0.0;_avgHeartRate=0;_heartRate=0;_hrSpots=[];}); }), const SizedBox(width: 15), Opacity(opacity: _isWorkingOut ? 0.3 : 1.0, child: _actionBtn(Icons.save, "저장", _handleSaveRecord)), const SizedBox(width: 15), _actionBtn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _saveToPrefs))))]);
  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Icon(i, color: Colors.white, size: 24))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
}

// --- 히스토리 및 통계 화면 ---
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records; final Function onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<WeightRecord> _weightRecords = [];
  final TextEditingController _weightController = TextEditingController();

  @override
  void initState() { super.initState(); _loadWeights(); }

  // 달력에 점을 찍기 위한 이벤트 로더
  List<WorkoutRecord> _getEventsForDay(DateTime day) {
    String formatted = DateFormat('yyyy-MM-dd').format(day);
    return widget.records.where((r) => r.date == formatted).toList();
  }

  Future<void> _loadWeights() async {
    final prefs = await SharedPreferences.getInstance();
    final String? res = prefs.getString('weight_records');
    if (res != null) {
      final List<dynamic> decoded = jsonDecode(res);
      setState(() { _weightRecords = decoded.map((item) => WeightRecord(item['date'], item['weight'])).toList(); });
    }
  }

  Future<void> _saveWeights() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('weight_records', jsonEncode(_weightRecords.map((r) => {'date': r.date, 'weight': r.weight}).toList()));
  }

  void _addWeightPopup() {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text("오늘의 체중", style: TextStyle(color: Colors.white)),
      content: TextField(controller: _weightController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: "kg 단위", suffixText: "kg")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
        ElevatedButton(onPressed: () {
          if (_weightController.text.isNotEmpty) {
            setState(() {
              String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
              _weightRecords.removeWhere((r) => r.date == today);
              _weightRecords.insert(0, WeightRecord(today, double.parse(_weightController.text)));
            });
            _saveWeights(); _weightController.clear(); Navigator.pop(context);
          }
        }, child: const Text("저장"))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    // 7일 통계 계산
    double weeklyCals = widget.records.where((r) => DateTime.parse(r.id).isAfter(DateTime.now().subtract(const Duration(days: 7)))).fold(0.0, (sum, r) => sum + r.calories);
    double currentWeight = _weightRecords.isEmpty ? 0.0 : _weightRecords.first.weight;
    final filteredRecords = widget.records.where((r) => _selectedDay == null || r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("운동 히스토리", style: TextStyle(color: Colors.white)), backgroundColor: Colors.black, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
      floatingActionButton: FloatingActionButton(onPressed: _addWeightPopup, backgroundColor: Colors.blueAccent, child: const Icon(Icons.monitor_weight, color: Colors.white)),
      body: Column(children: [
        // 상단 요약 배너 (다크 그레이 디자인)
        Container(
          margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white10)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _sumItem("7일 소모량", "${weeklyCals.toStringAsFixed(0)} kcal", Colors.orangeAccent),
            Container(width: 1, height: 30, color: Colors.white10),
            _sumItem("최근 체중", currentWeight > 0 ? "$currentWeight kg" : "입력 필요", Colors.blueAccent),
          ]),
        ),
        // 달력 (운동한 날 점 표시)
        TableCalendar(
          firstDay: DateTime.utc(2024, 1, 1), lastDay: DateTime.utc(2030, 12, 31), focusedDay: _focusedDay, locale: 'ko_KR',
          rowHeight: 42,
          eventLoader: _getEventsForDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
          calendarStyle: const CalendarStyle(
            markerDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
            selectedDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
          ),
          headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
        ),
        const Divider(color: Colors.white10, indent: 20, endIndent: 20),
        Expanded(child: filteredRecords.isEmpty ? const Center(child: Text("기록이 없습니다.", style: TextStyle(color: Colors.white24))) : ListView.builder(itemCount: filteredRecords.length, itemBuilder: (c, i) => _recordCard(filteredRecords[i]))),
      ]),
    );
  }

  Widget _sumItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(color: Colors.white54, fontSize: 11)), const SizedBox(height: 5), Text(v, style: TextStyle(color: c, fontSize: 17, fontWeight: FontWeight.bold))]);

  Widget _recordCard(WorkoutRecord r) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
    child: Row(children: [
      const CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.directions_bike, color: Colors.blueAccent, size: 20)),
      const SizedBox(width: 15),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.date, style: const TextStyle(fontWeight: FontWeight.bold)), Text("${r.duration.inMinutes}분 / 평균 ${r.avgHR}bpm", style: const TextStyle(color: Colors.white54, fontSize: 12))])),
      Text("${r.calories.toStringAsFixed(1)} kcal", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
    ]),
  );
}
