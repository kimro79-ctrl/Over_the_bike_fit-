import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  final String id, date;
  final int avgHR;
  final double calories;
  final Duration duration;

  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'avgHR': avgHR,
        'calories': calories,
        'durationSeconds': duration.inSeconds
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
  Timer? _workoutTimer;
  bool _isWorkingOut = false, _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  List<WorkoutRecord> _records = [];
  List<ScanResult> _filteredResults = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  // ✅ 1. 권한 설정 (Android 12 이상 완벽 대응)
  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List decoded = jsonDecode(res);
        _records = decoded.map((i) => WorkoutRecord(i['id'], i['date'], i['avgHR'], (i['calories'] as num).toDouble(), Duration(seconds: i['durationSeconds']))).toList();
      }
    });
  }

  // ✅ 2. 워치 스캔 (필터 제거 및 스캔 로직 정상화)
  void _showDeviceScanPopup() async {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _showToast("블루투스를 켜주세요");
      return;
    }
    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          var sub = FlutterBluePlus.onScanResults.listen((results) {
            if (mounted) setModalState(() => _filteredResults = results);
          });
          return Container(
            padding: const EdgeInsets.all(20),
            height: 400,
            child: Column(children: [
              const Text("워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredResults.length,
                  itemBuilder: (c, i) => ListTile(
                    leading: const Icon(Icons.watch, color: Colors.blueAccent),
                    title: Text(_filteredResults[i].device.platformName.isEmpty ? "알 수 없는 기기" : _filteredResults[i].device.platformName),
                    onTap: () { sub.cancel(); FlutterBluePlus.stopScan(); Navigator.pop(context); _connectToDevice(_filteredResults[i].device); },
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    ).then((_) => FlutterBluePlus.stopScan());
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() => _isWatchConnected = true);
      _listenHeartRate(device);
    } catch (e) { _showToast("연결 실패"); }
  }

  void _listenHeartRate(BluetoothDevice device) async {
    var services = await device.discoverServices();
    for (var service in services) {
      for (var c in service.characteristics) {
        if (c.uuid.toString().toLowerCase().contains("2a37")) {
          await c.setNotifyValue(true);
          c.onValueReceived.listen((value) {
            if (value.isNotEmpty) {
              int hr = value.length > 1 ? value[1] : value[0];
              if (mounted && hr > 0) {
                setState(() {
                  _heartRate = hr;
                  if (_isWorkingOut) {
                    _hrSpots.add(FlSpot(_duration.inSeconds.toDouble(), hr.toDouble()));
                    _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
                  }
                });
              }
            }
          });
        }
      }
    }
  }

  // ✅ 3. 칼로리 계산 (심박수 80 이상 기준 적용)
  void _calculateCalories() {
    if (_heartRate >= 80) {
      // 심박수 80부터 본격 소모 (강도에 따른 가중치)
      double intensity = (_heartRate - 80) * 0.006; 
      _calories += 0.15 + intensity; 
    } else {
      // 80 미만은 아주 미미한 기초 소모만 반영
      _calories += 0.01;
    }
  }

  // ✅ 4. 데이터 저장 로직 (누락 없이 구현)
  void _saveWorkout() async {
    if (_duration.inSeconds < 10) {
      _showToast("운동 시간이 너무 짧습니다.");
      return;
    }
    final record = WorkoutRecord(
      DateTime.now().toString(),
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      _avgHeartRate,
      _calories,
      _duration,
    );
    setState(() => _records.insert(0, record));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(_records.map((r) => r.toJson()).toList()));
    _showToast("기록이 저장되었습니다.");
  }

  // ✅ 5. 리셋 팝업 로직 (운동 중 방지)
  void _handleReset() {
    if (_isWorkingOut) {
      showDialog(context: context, builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("알림", style: TextStyle(color: Colors.white)),
        content: const Text("운동이 진행 중일 때는 리셋할 수 없습니다.\n먼저 일시정지 해주세요.", style: TextStyle(color: Colors.white70)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인", style: TextStyle(color: Colors.greenAccent)))],
      ));
    } else {
      setState(() { _duration = Duration.zero; _calories = 0.0; _heartRate = 0; _avgHeartRate = 0; _hrSpots = []; });
      _showToast("데이터가 초기화되었습니다.");
    }
  }

  void _showToast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.black)))),
        SafeArea(child: Column(children: [
          const SizedBox(height: 40),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            GestureDetector(
              onTap: _showDeviceScanPopup,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.greenAccent)),
                child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ])),
          const Spacer(),
          _buildGoalBar(),
          const SizedBox(height: 20),
          _buildDataBanner(), // ✅ 데이터 UI 유지
          const SizedBox(height: 30),
          _buildControlButtons(), // ✅ 버튼 로직 연결 완료
          const SizedBox(height: 40),
        ])),
      ]),
    );
  }

  Widget _buildGoalBar() => Container(margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15)), child: Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CALORIE GOAL", style: TextStyle(fontSize: 10, color: Colors.white70)), Text("${_calories.toInt()} / 300 kcal", style: const TextStyle(color: Colors.greenAccent))]),
    const SizedBox(height: 10),
    LinearProgressIndicator(value: (_calories / 300).clamp(0, 1), color: Colors.greenAccent, backgroundColor: Colors.white12),
  ]));

  Widget _buildDataBanner() => Container(margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _statItem("심박수", "$_heartRate", Colors.greenAccent),
    _statItem("평균", "$_avgHeartRate", Colors.redAccent),
    _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
    _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
  ]));

  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);

  Widget _buildControlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _circleBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", onTap: () {
      setState(() { _isWorkingOut = !_isWorkingOut; });
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() {
          _duration += const Duration(seconds: 1);
          _calculateCalories(); // ✅ 매 초마다 심박수 80 기준 칼로리 계산
        }));
      } else { _workoutTimer?.cancel(); }
    }),
    const SizedBox(width: 15),
    _circleBtn(Icons.refresh, "리셋", onTap: _handleReset),
    const SizedBox(width: 15),
    _circleBtn(Icons.save, "저장", onTap: _saveWorkout), // ✅ 저장 함수 연결 완료
    const SizedBox(width: 15),
    _circleBtn(Icons.calendar_month, "기록", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _loadInitialData)))),
  ]);

  Widget _circleBtn(IconData i, String l, {VoidCallback? onTap}) => Column(children: [
    GestureDetector(onTap: onTap, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15)), child: Icon(i, color: Colors.white))),
    const SizedBox(height: 6),
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70)),
  ]);
}

// ✅ 기록 리포트 화면 (UI 복구 완료)
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: const Text("기록 리포트", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.white, elevation: 0, iconTheme: const IconThemeData(color: Colors.black)),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(color: const Color(0xFF64748B), borderRadius: BorderRadius.circular(15)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
            Text("나의 현재 체중", style: TextStyle(color: Colors.white, fontSize: 16)),
            Text("69.7kg", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _tab("일간", Colors.redAccent), _tab("주간", Colors.orangeAccent), _tab("월간", Colors.blueAccent),
        ]),
        const SizedBox(height: 10),
        TableCalendar(
          focusedDay: DateTime.now(), firstDay: DateTime(2020), lastDay: DateTime(2030),
          calendarFormat: CalendarFormat.month,
          headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(color: Colors.black)),
          calendarStyle: const CalendarStyle(defaultTextStyle: TextStyle(color: Colors.black), weekendTextStyle: TextStyle(color: Colors.red)),
        ),
        Expanded(child: ListView.builder(
          itemCount: widget.records.length,
          itemBuilder: (c, i) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: Colors.white,
            child: ListTile(
              leading: const Icon(Icons.directions_bike, color: Colors.blueAccent),
              title: Text("${widget.records[i].calories.toInt()} kcal 소모", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              subtitle: Text("${widget.records[i].date} / ${widget.records[i].duration.inMinutes}분 운동", style: const TextStyle(color: Colors.black54)),
            ),
          ),
        )),
      ]),
    );
  }
  Widget _tab(String t, Color c) => Container(padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)), child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12)));
}
