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
// ✅ 지도 및 GPS 라이브러리 추가
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong2.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SplashScreen(),
  ));
}

// ✅ 스플래시 화면 (기존 유지)
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);
  @override _SplashScreenState createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> {
  @override void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const BikeFitApp())));
  }
  @override Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text("Indoor Bike Fit", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2))));
  }
}

// ✅ 데이터 모델 업데이트
class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  final double distanceKm; // 주행 거리 추가
  final String type; // 'indoor' 또는 'outdoor'

  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration, {this.distanceKm = 0.0, this.type = 'indoor'});

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories,
    'durationSeconds': duration.inSeconds, 'distanceKm': distanceKm, 'type': type
  };

  factory WorkoutRecord.fromJson(Map<String, dynamic> json) => WorkoutRecord(
    json['id'], json['date'], json['avgHR'], (json['calories'] as num).toDouble(),
    Duration(seconds: json['durationSeconds']),
    distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
    type: json['type'] ?? 'indoor'
  );
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) {
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
  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

  @override
  void initState() { super.initState(); _loadInitialData(); _requestPermissions(); }

  Future<void> _requestPermissions() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location, Permission.locationWhenInUse].request();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord.fromJson(item)).toList();
      }
    });
  }

  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E1E), isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), builder: (context) => StatefulBuilder(builder: (context, setModalState) {
      _scanSubscription = FlutterBluePlus.onScanResults.listen((results) { if (mounted) setModalState(() { _filteredResults = results.where((r) => r.device.platformName.isNotEmpty).toList(); }); });
      return Container(padding: const EdgeInsets.all(20), height: MediaQuery.of(context).size.height * 0.4, child: Column(children: [Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))), const SizedBox(height: 20), const Text("워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Expanded(child: ListView.builder(itemCount: _filteredResults.length, itemBuilder: (context, index) => ListTile(leading: const Icon(Icons.watch, color: Colors.blueAccent), title: Text(_filteredResults[index].device.platformName), onTap: () { Navigator.pop(context); _connectToDevice(_filteredResults[index].device); }))) ]));
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

  void _showToast(String msg) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1))); }

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SizedBox(height: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom, child: Column(children: [
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5)), _connectButton()]),
          const SizedBox(height: 25),
          _chartArea(),
          const Spacer(),
          _goalArea(progress),
          const SizedBox(height: 20),
          _dataBanner(),
          const SizedBox(height: 30),
          _controlButtons(),
          const SizedBox(height: 40),
        ]))))),
      ]),
    );
  }

  Widget _connectButton() => GestureDetector(onTap: _showDeviceScanPopup, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.greenAccent)), child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold))));
  Widget _chartArea() => SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])));
  Widget _goalArea(double p) => Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)), child: Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CALORIE GOAL", style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)), Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))]),
    const SizedBox(height: 10),
    ClipRRect(borderRadius: BorderRadius.circular(5), child: SizedBox(height: 10, child: LinearProgressIndicator(value: p, backgroundColor: Colors.white12, color: Colors.greenAccent))),
  ]));
  Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.greenAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);

  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", () { 
      setState(() { _isWorkingOut = !_isWorkingOut; if (_isWorkingOut) { _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) { setState(() { _duration += const Duration(seconds: 1); if (_heartRate >= 90) { _calories += 0.15; } }); }); } else { _workoutTimer?.cancel(); } }); 
    }),
    const SizedBox(width: 12),
    _actionBtn(Icons.directions_run, "실외주행", () async {
      await Navigator.push(context, MaterialPageRoute(builder: (c) => OutdoorMapScreen(records: _records)));
      _loadInitialData();
    }),
    const SizedBox(width: 12),
    _actionBtn(Icons.save, "저장", () async {
      if (_isWorkingOut) { _showToast("일시정지 후 저장하세요."); return; }
      if (_duration.inSeconds < 5) { _showToast("기록이 너무 짧습니다."); return; }
      final newRec = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
      setState(() { _records.insert(0, newRec); });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_records', jsonEncode(_records.map((r) => r.toJson()).toList()));
      _showToast("저장 완료!");
    }),
    const SizedBox(width: 12),
    _actionBtn(Icons.calendar_month, "기록", () async {
      await Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _loadInitialData)));
      _loadInitialData();
    }),
  ]);

  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white, size: 22))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 9, color: Colors.white70))]);
}

// ✅ 실외 주행 지도 화면
class OutdoorMapScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const OutdoorMapScreen({Key? key, required this.records}) : super(key: key);
  @override _OutdoorMapScreenState createState() => _OutdoorMapScreenState();
}
class _OutdoorMapScreenState extends State<OutdoorMapScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _points = [];
  double _dist = 0.0;
  bool _isTracking = false;
  StreamSubscription<Position>? _stream;
  DateTime? _start;

  void _toggleTracking() async {
    if (_isTracking) {
      _stream?.cancel();
      _saveOutdoor();
      setState(() => _isTracking = false);
    } else {
      LocationPermission p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied) return;
      setState(() { _isTracking = true; _points.clear(); _dist = 0.0; _start = DateTime.now(); });
      _stream = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)).listen((pos) {
        LatLng loc = LatLng(pos.latitude, pos.longitude);
        setState(() {
          if (_points.isNotEmpty) _dist += Geolocator.distanceBetween(_points.last.latitude, _points.last.longitude, loc.latitude, loc.longitude) / 1000;
          _points.add(loc); _mapController.move(loc, 16);
        });
      });
    }
  }

  void _saveOutdoor() async {
    if (_dist < 0.01) return;
    final newRec = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), 0, _dist * 60, DateTime.now().difference(_start!), distanceKm: _dist, type: 'outdoor');
    widget.records.insert(0, newRec);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(widget.records.map((r) => r.toJson()).toList()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("주행 기록이 저장되었습니다.")));
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("실외 주행"), backgroundColor: Colors.black),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: const MapOptions(initialCenter: LatLng(37.56, 126.97), initialZoom: 15), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          PolylineLayer(polylines: [Polyline(points: _points, color: Colors.blueAccent, strokeWidth: 5)]),
        ]),
        Positioned(bottom: 20, left: 20, right: 20, child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("${_dist.toStringAsFixed(2)} km", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 15),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _isTracking ? Colors.redAccent : Colors.blueAccent, minimumSize: const Size(double.infinity, 50)), onPressed: _toggleTracking, child: Text(_isTracking ? "주행 종료 및 저장" : "주행 시작"))
        ])))
      ]),
    );
  }
}

// ✅ 기록 리포트 (차트 및 통계 통합)
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}
class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  double _weight = 70.0;
  String _tab = "일간";

  @override void initState() { super.initState(); _selectedDay = _focusedDay; _loadWeight(); }
  Future<void> _loadWeight() async { final prefs = await SharedPreferences.getInstance(); setState(() => _weight = prefs.getDouble('last_weight') ?? 70.0); }

  @override Widget build(BuildContext context) {
    final daily = widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    final totalKm = widget.records.fold(0.0, (prev, e) => prev + e.distanceKm);

    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
        body: SingleChildScrollView(child: Column(children: [
          // 상단 요약 바 (체중 & 마일리지)
          Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFF546E7A), borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("누적 마일리지", style: TextStyle(color: Colors.white70, fontSize: 11)), Text("${totalKm.toStringAsFixed(1)} km", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Text("현재 체중", style: TextStyle(color: Colors.white70, fontSize: 11)), Text("${_weight}kg", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))]),
          ])),
          // 탭 버튼
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            _tabBtn("일간", Colors.redAccent), const SizedBox(width: 8),
            _tabBtn("주간", Colors.orangeAccent), const SizedBox(width: 8),
            _tabBtn("월간", Colors.blueAccent),
          ])),
          // 달력 또는 차트 영역
          if (_tab == "일간") Container(
            margin: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
            child: TableCalendar(
              locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay, rowHeight: 35,
              headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
              calendarStyle: const CalendarStyle(selectedDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
            ),
          ) else _buildChart(),
          // 기록 리스트
          ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: daily.length, itemBuilder: (context, i) {
            final r = daily[i];
            return Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: ListTile(
              leading: Icon(r.type == 'indoor' ? Icons.directions_bike : Icons.directions_run, color: Colors.blueAccent),
              title: Text("${r.calories.toInt()} kcal / ${r.type == 'indoor' ? '실내' : '실외'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text("${r.duration.inMinutes}분 / ${r.type == 'indoor' ? '${r.avgHR} bpm' : '${r.distanceKm.toStringAsFixed(1)} km'}"),
            ));
          }),
        ])),
      ),
    );
  }

  Widget _tabBtn(String l, Color c) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _tab == l ? c : Colors.white, foregroundColor: _tab == l ? Colors.white : Colors.black54, elevation: 0), onPressed: () => setState(() => _tab = l), child: Text(l)));
  
  Widget _buildChart() => Container(height: 150, margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: BarChart(BarChartData(
    alignment: BarChartAlignment.spaceAround, maxY: 20, barGroups: List.generate(7, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: 5.0 + i, color: Colors.blueAccent, width: 12)])),
    gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
  )));
}
