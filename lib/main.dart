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
  // 가로 모드 방지
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  runApp(const BikeFitApp());
}

// [데이터 모델]
class WorkoutRecord {
  final String id, date;
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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'Pretendard', // 혹은 시스템 기본 폰트
      ),
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
  int _heartRate = 0, _avgHeartRate = 0;
  double _calories = 0.0, _goalCalories = 300.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false, _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];
  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    // ✅ 앱 시작 시 권한 체크 (사용자님 로직 반영)
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  Future<void> _requestPermissions() async {
    // 현재 상태 확인
    var scanStatus = await Permission.bluetoothScan.status;
    var connectStatus = await Permission.bluetoothConnect.status;
    var locationStatus = await Permission.location.status;

    // 하나라도 영구 거부라면 설정창으로
    if (scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied || locationStatus.isPermanentlyDenied) {
      _showToast("권한이 영구 거부되었습니다. 설정에서 허용해주세요.");
      await openAppSettings();
      return;
    }

    // 권한 요청
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(item['id'] ?? DateTime.now().toString(), item['date'], item['avgHR'], (item['calories'] as num).toDouble(), Duration(seconds: item['durationSeconds'] ?? 0))).toList();
      }
    });
  }

  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    await _requestPermissions();
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _showToast("블루투스를 켜주세요.");
      return;
    }

    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
          if (mounted) setModalState(() { _filteredResults = results; });
        });
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.5,
          child: Column(children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text("워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Expanded(
              child: _filteredResults.isEmpty 
                  ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent)) 
                  : ListView.builder(
                      itemCount: _filteredResults.length,
                      itemBuilder: (context, index) {
                        final device = _filteredResults[index].device;
                        final name = device.platformName.isEmpty ? "알 수 없는 기기" : device.platformName;
                        return ListTile(
                          leading: const Icon(Icons.watch, color: Colors.blueAccent),
                          title: Text(name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(device.remoteId.toString(), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          onTap: () { Navigator.pop(context); _connectToDevice(device); },
                        );
                      },
                    ),
            )
          ]),
        );
      }),
    ).whenComplete(() {
      FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      _setupDevice(device);
    } catch (e) {
      _showToast("연결 실패");
    }
  }

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

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
  }

  // 💎 [사용자님 원본 UI 레이아웃]
  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: Stack(
        children: [
          // ✅ 배경 이미지 (Assets에 있는 파일 사용)
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
            ),
          ),
          // 그라데이션 오버레이 (가독성용)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                 Fergradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.3), Colors.black.withOpacity(0.7)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  // 헤더
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Indoor bike fit', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.2)),
                      _connectButton(),
                    ],
                  ),
                  const SizedBox(height: 40),
                  // 차트 영역
                  _chartArea(),
                  const Spacer(),
                  // 목표 바
                  _goalBar(progress),
                  const SizedBox(height: 25),
                  // 통계 배너
                  _dataBanner(),
                  const SizedBox(height: 35),
                  // 하단 컨트롤 버튼
                  _controlButtons(),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectButton() => GestureDetector(
    onTap: _showDeviceScanPopup,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _isWatchConnected ? Colors.greenAccent : Colors.white30, width: 1.5),
      ),
      child: Text(
        _isWatchConnected ? "CONNECTED" : "CONNECT WATCH",
        style: TextStyle(color: _isWatchConnected ? Colors.greenAccent : Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    ),
  );

  Widget _chartArea() => SizedBox(
    height: 100,
    child: LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots,
            isCurved: true,
            color: Colors.greenAccent,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: Colors.greenAccent.withOpacity(0.2)),
          ),
        ],
      ),
    ),
  );

  Widget _goalBar(double progress) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.6),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white10),
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("CALORIE GOAL", style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold)),
            Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(fontSize: 14, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(value: progress, minHeight: 12, backgroundColor: Colors.white12, color: Colors.greenAccent),
        ),
      ],
    ),
  );

  Widget _dataBanner() => Container(
    padding: const EdgeInsets.symmetric(vertical: 25),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: Colors.white10),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _statItem("HEART RATE", "$_heartRate", Colors.greenAccent),
        _statItem("AVG HR", "$_avgHeartRate", Colors.redAccent),
        _statItem("CALORIES", _calories.toStringAsFixed(1), Colors.orangeAccent),
        _statItem("DURATION", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
      ],
    ),
  );

  Widget _statItem(String l, String v, Color c) => Column(
    children: [
      Text(l, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c)),
    ],
  );

  Widget _controlButtons() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "START", () {
        setState(() {
          _isWorkingOut = !_isWorkingOut;
          if (_isWorkingOut) {
            _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
              setState(() {
                _duration += const Duration(seconds: 1);
                if (_heartRate >= 90) _calories += 0.12; // 심박수에 따른 보정
              });
            });
          } else {
            _workoutTimer?.cancel();
          }
        });
      }),
      const SizedBox(width: 20),
      _actionBtn(Icons.refresh, "RESET", () {
        if (!_isWorkingOut) {
          setState(() { _duration = Duration.zero; _calories = 0.0; _heartRate = 0; _hrSpots = []; _timeCounter = 0; });
        }
      }),
      const SizedBox(width: 20),
      _actionBtn(Icons.save_rounded, "SAVE", () async {
        if (_isWorkingOut) return;
        final newRec = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
        setState(() { _records.insert(0, newRec); });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('workout_records', jsonEncode(_records.map((r) => r.toJson()).toList()));
        _showToast("기록이 저장되었습니다.");
      }),
      const SizedBox(width: 20),
      _actionBtn(Icons.calendar_today_rounded, "HISTORY", () {
        Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _loadInitialData)));
      }),
    ],
  );

  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(
    children: [
      GestureDetector(
        onTap: t,
        child: Container(
          width: 65, height: 65,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(i, color: Colors.white, size: 28),
        ),
      ),
      const SizedBox(height: 8),
      Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60, fontWeight: FontWeight.bold)),
    ],
  );
}

// [기록 화면 및 기타 코드는 이전과 동일]
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  @override void initState() { super.initState(); _selectedDay = _focusedDay; }
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Workout History")),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() { _selectedDay = selectedDay; _focusedDay = focusedDay; });
            },
          ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).length,
              itemBuilder: (context, index) {
                final r = widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList()[index];
                return ListTile(
                  title: Text("${r.calories.toInt()} kcal"),
                  subtitle: Text("${r.duration.inMinutes} min / Avg: ${r.avgHR} bpm"),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
