import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // 블루투스 패키지
import 'package:permission_handler/permission_handler.dart'; // 권한 패키지
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

// 1. 스플래시 화면 (블랙 배경 + 텍스트 디자인)
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const WorkoutScreen()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("INDOOR", style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const Text("BIKE FIT", style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(height: 15),
                Text("Indoor cycling studio", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
              ],
            ),
          ),
          const Positioned(right: 40, bottom: 60, child: Icon(Icons.star, color: Colors.white, size: 30))
        ],
      ),
    );
  }
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
      home: const SplashScreen(),
    );
  }
}

// 2. 메인 운동 화면 (워치 연결 기능 추가)
class WorkoutRecord {
  final String id, date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds};
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _timer;
  bool _isWorking = false;
  List<WorkoutRecord> _records = [];
  
  // 블루투스 관련 변수
  bool _isConnecting = false;
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _hrSubscription;

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final res = prefs.getString('workout_records');
    if (res != null) {
      final List decoded = jsonDecode(res);
      setState(() {
        _records = decoded.map((item) => WorkoutRecord(item['id'], item['date'], item['avgHR'], (item['calories'] as num).toDouble(), Duration(seconds: item['durationSeconds']))).toList();
      });
    }
  }

  // ✅ 워치 연결 팝업 및 스캔 로직
  void _startScan() async {
    // 권한 체크
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StreamBuilder<List<ScanResult>>(
        stream: FlutterBluePlus.onScanResults,
        builder: (context, snapshot) {
          final results = snapshot.data ?? [];
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text("워치 연결", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: () => FlutterBluePlus.startScan(timeout: const Duration(seconds: 5)), child: const Text("스캔 시작")),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (c, i) => ListTile(
                      title: Text(results[i].device.platformName.isEmpty ? "알 수 없는 기기" : results[i].device.platformName),
                      subtitle: Text(results[i].device.remoteId.toString()),
                      onTap: () {
                        Navigator.pop(context);
                        _connectToWatch(results[i].device);
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _connectToWatch(BluetoothDevice device) async {
    setState(() => _isConnecting = true);
    try {
      await device.connect();
      _connectedDevice = device;
      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid.toString().contains("180d")) { // 심박수 서비스 UUID
          for (var c in s.characteristics) {
            if (c.uuid.toString().contains("2a37")) { // 심박수 측정 특성 UUID
              await c.setNotifyValue(true);
              _hrSubscription = c.lastValueStream.listen((data) {
                if (data.isNotEmpty) {
                  setState(() => _heartRate = data[1]); // 심박수 데이터 추출
                }
              });
            }
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("연결 실패")));
    }
    setState(() => _isConnecting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.7, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s) => Container(color: Colors.black)))),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              const SizedBox(height: 40),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                GestureDetector(
                  onTap: _startScan,
                  child: Icon(Icons.watch, color: _connectedDevice != null ? Colors.greenAccent : Colors.white24),
                ),
              ]),
              const Spacer(),
              _statRow(),
              const SizedBox(height: 30),
              _btnRow(),
              const SizedBox(height: 40),
            ]),
          ),
        )
      ]),
    );
  }

  Widget _statRow() => Container(
    padding: const EdgeInsets.symmetric(vertical: 20),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _item("심박수", "$_heartRate", Colors.greenAccent),
      _item("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
      _item("시간", "${_duration.inMinutes}:${(_duration.inSeconds%60).toString().padLeft(2,'0')}", Colors.blueAccent),
    ]),
  );

  Widget _item(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c))]);

  Widget _btnRow() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _circleBtn(_isWorking ? Icons.pause : Icons.play_arrow, () {
      setState(() {
        _isWorking = !_isWorking;
        if(_isWorking) { _timer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() { _duration += const Duration(seconds: 1); _calories += 0.1; })); }
        else { _timer?.cancel(); }
      });
    }),
    const SizedBox(width: 15),
    _circleBtn(Icons.refresh, () => setState(() { _duration = Duration.zero; _calories = 0.0; _heartRate = 0; })),
    const SizedBox(width: 15),
    _circleBtn(Icons.save, () async {
      final r = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _heartRate, _calories, _duration);
      _records.insert(0, r);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_records', jsonEncode(_records.map((e)=>e.toJson()).toList()));
    }),
    const SizedBox(width: 15),
    _circleBtn(Icons.calendar_month, () => Navigator.push(context, MaterialPageRoute(builder: (c)=>HistoryScreen(records: _records, onSync: _loadData)))),
  ]);

  Widget _circleBtn(IconData i, VoidCallback t) => GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white10, shape: BoxShape.circle, border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white)));
}

// 3. 기록 리포트 (체중/일월주간/길게눌러삭제)
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focused = DateTime.now();
  DateTime? _selected;
  double _weight = 70.0;
  late List<WorkoutRecord> _cur;

  @override
  void initState() { super.initState(); _cur = List.from(widget.records); _selected = _focused; _loadWeight(); }

  Future<void> _loadWeight() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _weight = prefs.getDouble('u_weight') ?? 70.0; });
  }

  void _del(WorkoutRecord r) {
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text("삭제"), content: const Text("정말 삭제할까요?"), actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")),
      TextButton(onPressed: () async {
        setState(() { _cur.removeWhere((i) => i.id == r.id); });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('workout_records', jsonEncode(_cur.map((e)=>e.toJson()).toList()));
        widget.onSync(); Navigator.pop(c);
      }, child: const Text("삭제", style: TextStyle(color: Colors.red))),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final daily = _cur.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selected!)).toList();
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
        body: Column(children: [
          Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFF607D8B), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("나의 현재 체중", style: TextStyle(color: Colors.white)), Text("${_weight}kg", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            _btn("일간", Colors.redAccent), const SizedBox(width: 8),
            _btn("주간", Colors.orangeAccent), const SizedBox(width: 8),
            _btn("월간", Colors.blueAccent),
          ])),
          Container(margin: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: TableCalendar(
            locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focused, rowHeight: 40,
            selectedDayPredicate: (d) => isSameDay(_selected, d),
            onDaySelected: (s, f) => setState(() { _selected = s; _focused = f; }),
          )),
          Expanded(child: ListView.builder(itemCount: daily.length, itemBuilder: (c, i) => Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: ListTile(
            onLongPress: () => _del(daily[i]),
            leading: const Icon(Icons.directions_bike, color: Colors.blueAccent),
            title: Text("${daily[i].calories.toInt()} kcal"),
            subtitle: Text("${daily[i].duration.inMinutes}분 운동"),
          )))),
        ]),
      ),
    );
  }

  Widget _btn(String l, Color c) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white, elevation: 0), onPressed: (){}, child: Text(l)));
}
