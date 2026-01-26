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
      theme: ThemeData(
        useMaterial3: true, 
        brightness: Brightness.dark, 
        scaffoldBackgroundColor: Colors.black,
      ),
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
  double _goalCalories = 300.0; // 기본 목표 칼로리
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
  void initState() { 
    super.initState(); 
    _loadRecords(); 
    _loadGoal();
  }

  // 데이터 로드/저장 로직
  Future<void> _loadGoal() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _goalCalories = prefs.getDouble('goal_calories') ?? 300.0; });
  }

  Future<void> _saveGoal(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('goal_calories', value);
  }

  // 블루투스 연결 팝업
  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    showModalBottomSheet(
      context: context, 
      backgroundColor: const Color(0xFF1E1E1E), 
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), 
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) { 
          if (mounted) setModalState(() { _filteredResults = results.where((r) => r.device.platformName.isNotEmpty).toList(); }); 
        });
        return Container(
          padding: const EdgeInsets.all(20), 
          height: MediaQuery.of(context).size.height * 0.4,
          child: Column(children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text("워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Expanded(child: _filteredResults.isEmpty 
              ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent)) 
              : ListView.builder(itemCount: _filteredResults.length, itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.watch, color: Colors.blueAccent), 
                  title: Text(_filteredResults[index].device.platformName), 
                  onTap: () { Navigator.pop(context); _connectToDevice(_filteredResults[index].device); }
                ))) 
          ]));
      })).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });
  }

  // 목표 설정 팝업
  void _showGoalSettings() {
    final controller = TextEditingController(text: _goalCalories.toInt().toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("목표 칼로리 설정", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, color: Colors.greenAccent, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(suffixText: "kcal", enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소", style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () {
            setState(() { _goalCalories = double.tryParse(controller.text) ?? 300.0; });
            _saveGoal(_goalCalories);
            Navigator.pop(context);
          }, child: const Text("확인", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );
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
    if (_duration.inSeconds < 5) { _showToast("운동 시간이 너무 짧습니다."); return; }
    String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    setState(() { _records.insert(0, WorkoutRecord(DateTime.now().millisecondsSinceEpoch.toString(), dateStr, _avgHeartRate, _calories, _duration)); });
    _saveToPrefs(); _showToast("저장 완료!");
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

  void _showToast(String msg) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating)); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Indoor bike fit', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              _connectButton(),
            ]),
          ),
          
          // 중앙 아이콘 섹션
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_bike, size: 70, color: Colors.greenAccent.withOpacity(_isWorkingOut ? 0.8 : 0.2)),
                  const SizedBox(height: 10),
                  Text(_isWorkingOut ? "PUSH HARDER!" : "READY TO START", style: TextStyle(fontSize: 12, color: Colors.white24, letterSpacing: 2)),
                ],
              ),
            ),
          ),

          // 차트 영역
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _chartArea()),
          
          const SizedBox(height: 30),

          // ✅ 슬림 목표 달성 바
          _goalProgressBar(),

          // 데이터 배너 (4칸)
          _dataBanner(),

          const SizedBox(height: 30),

          // 하단 버튼
          _controlButtons(),
          
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _connectButton() => GestureDetector(onTap: _showDeviceScanPopup, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.greenAccent.withOpacity(0.5))), child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold))));
  
  Widget _chartArea() => SizedBox(height: 50, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])));

  // ✅ 슬림 목표 바 위젯
  Widget _goalProgressBar() {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
      child: Column(
        children: [
          GestureDetector(
            onTap: _showGoalSettings,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("GOAL PROGRESS", style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
              Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 8),
          Stack(children: [
            Container(height: 5, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              height: 5,
              width: (MediaQuery.of(context).size.width - 50) * progress,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.greenAccent, Colors.blueAccent]),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.greenAccent.withOpacity(0.2), blurRadius: 5)],
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _dataBanner() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    padding: const EdgeInsets.symmetric(vertical: 20),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _statItem("심박수", "$_heartRate", Colors.greenAccent),
      _statItem("평균", "$_avgHeartRate", Colors.redAccent),
      _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
      _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)
    ]),
  );

  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);

  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", () {
      setState(() {
        _isWorkingOut = !_isWorkingOut;
        if (_isWorkingOut) {
          _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() {
            _duration += const Duration(seconds: 1);
            if (_heartRate >= 95) _calories += (95 * 0.012 * (1/60));
          }));
        } else { _workoutTimer?.cancel(); }
      });
    }),
    const SizedBox(width: 20),
    _actionBtn(Icons.refresh, "리셋", () { if(!_isWorkingOut) setState((){_duration=Duration.zero;_calories=0.0;_avgHeartRate=0;_heartRate=0;_hrSpots=[];}); }),
    const SizedBox(width: 20),
    _actionBtn(Icons.save, "저장", _handleSaveRecord),
    const SizedBox(width: 20),
    _actionBtn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _saveToPrefs))))
  ]);

  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(15)), child: Icon(i, color: Colors.white, size: 24))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
}

// --- 히스토리 화면 (삭제 기능 포함) ---
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final Function onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<WeightRecord> _weightRecords = [];

  @override
  void initState() { super.initState(); _loadWeights(); }

  Future<void> _loadWeights() async {
    final prefs = await SharedPreferences.getInstance();
    final String? res = prefs.getString('weight_records');
    if (res != null) {
      final List<dynamic> decoded = jsonDecode(res);
      setState(() { _weightRecords = decoded.map((item) => WeightRecord(item['date'], item['weight'])).toList(); });
    }
  }

  void _confirmDelete(WorkoutRecord record) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text("삭제", style: TextStyle(color: Colors.black)),
      content: const Text("이 기록을 삭제하시겠습니까?", style: TextStyle(color: Colors.black87)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
        TextButton(onPressed: () { setState(() { widget.records.removeWhere((r) => r.id == record.id); }); widget.onSync(); Navigator.pop(context); }, child: const Text("삭제", style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.records.where((r) => _selectedDay == null || r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.transparent, elevation: 0),
        body: SingleChildScrollView(child: Column(children: [
          _buildCalendarSection(),
          const SizedBox(height: 10),
          ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: filtered.length, itemBuilder: (c, i) => _buildRecordCard(filtered[i])),
        ])),
      ),
    );
  }

  Widget _buildCalendarSection() => Container(
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: TableCalendar(
      locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay,
      rowHeight: 35, headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
    ),
  );

  Widget _buildRecordCard(WorkoutRecord r) => GestureDetector(
    onLongPress: () => _confirmDelete(r),
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        const Icon(Icons.directions_bike, color: Colors.blueAccent),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.date, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text("${r.duration.inMinutes}분 / ${r.avgHR}bpm", style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ])),
        Text("${r.calories.toInt()} kcal", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
      ]),
    ),
  );
}
