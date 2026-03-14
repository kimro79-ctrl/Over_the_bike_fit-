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

// 모델
class WorkoutRecord {
  final String id;
  final String date;
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
      theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black),
      home: const AssetSplashScreen(),
    );
  }
}

// 스플래시
class AssetSplashScreen extends StatefulWidget {
  const AssetSplashScreen({Key? key}) : super(key: key);

  @override
  State<AssetSplashScreen> createState() => _AssetSplashScreenState();
}

class _AssetSplashScreenState extends State<AssetSplashScreen> {

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {

    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.sensors,
    ].request();

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => const WorkoutScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
        body: Center(
            child: Text("BIKE FIT",
                style:
                    TextStyle(fontSize: 32, fontWeight: FontWeight.bold))));
  }
}

// 메인 운동 화면
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {

  int _heartRate = 0;
  int _avgHeartRate = 0;

  double _calories = 0.0;
  double _goalCalories = 300.0;

  Duration _duration = Duration.zero;

  Timer? _workoutTimer;

  bool _isWorkingOut = false;
  bool _isWatchConnected = false;

  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;

  List<WorkoutRecord> _records = [];

  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

  BluetoothDevice? _connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _autoReconnectWatch();
  }

  Future<void> _loadInitialData() async {

    final prefs = await SharedPreferences.getInstance();

    setState(() {

      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;

      final String? res = prefs.getString('workout_records');

      if (res != null) {

        final List decoded = jsonDecode(res);

        _records = decoded
            .map((item) => WorkoutRecord(
                  item['id'] ?? "",
                  item['date'] ?? "",
                  item['avgHR'] ?? 0,
                  (item['calories'] as num).toDouble(),
                  Duration(seconds: item['durationSeconds'] ?? 0),
                ))
            .toList();
      }
    });
  }

  Future<void> _autoReconnectWatch() async {

    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString("last_watch_id");

    if (id == null) return;

    try {

      BluetoothDevice device = BluetoothDevice.fromId(id);

      await device.connect(timeout: const Duration(seconds: 10));

      _setupDevice(device);

    } catch (_) {}
  }

  Future<void> _saveWorkout() async {

    if (_duration.inSeconds < 10) return;

    final newRecord = WorkoutRecord(
      DateTime.now().millisecondsSinceEpoch.toString(),
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      _avgHeartRate,
      _calories,
      _duration,
    );

    _records.insert(0, newRecord);

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
        'workout_records',
        jsonEncode(_records.map((r) => r.toJson()).toList()));

    _showToast("운동 기록이 저장되었습니다.");
  }

  void _showDeviceScanPopup() async {

    if (_isWatchConnected) return;

    if (await FlutterBluePlus.isOn == false) {
      _showToast("블루투스를 켜주세요");
      return;
    }

    _filteredResults.clear();

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: true,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {

          _scanSubscription =
              FlutterBluePlus.onScanResults.listen((results) {

            if (mounted) {

              setModalState(() {

                _filteredResults = results
                    .where((r) =>
                        (r.device.platformName.isNotEmpty ||
                            r.advertisementData.advName.isNotEmpty))
                    .toList();
              });
            }
          });

          return Container(
            padding: const EdgeInsets.all(20),
            height: MediaQuery.of(context).size.height * 0.4,
            child: Column(children: [

              const Text("워치 검색",
                  style: TextStyle(fontWeight: FontWeight.bold)),

              const SizedBox(height: 10),

              Expanded(
                child: _filteredResults.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _filteredResults.length,
                        itemBuilder: (context, index) {

                          final r = _filteredResults[index];

                          String name = r.device.platformName.isEmpty
                              ? r.advertisementData.advName
                              : r.device.platformName;

                          return ListTile(
                            leading: const Icon(Icons.watch,
                                color: Colors.blueAccent),
                            title: Text(name),
                            onTap: () {
                              Navigator.pop(context);
                              _connectToDevice(r.device);
                            },
                          );
                        },
                      ),
              )
            ]),
          );
        },
      ),
    ).whenComplete(() {

      FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();

    });
  }

  void _connectToDevice(BluetoothDevice device) async {

    try {

      await device.connect(timeout: const Duration(seconds: 10));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("last_watch_id", device.remoteId.str);

      _setupDevice(device);

    } catch (e) {

      _showToast("연결 실패");

    }
  }

  void _setupDevice(BluetoothDevice device) async {

    _connectedDevice = device;

    _connectionSub?.cancel();

    _connectionSub =
        device.connectionState.listen((state) {

      if (state ==
          BluetoothConnectionState.disconnected) {

        setState(() {
          _isWatchConnected = false;
        });

        _autoReconnectWatch();
      }
    });

    setState(() {
      _isWatchConnected = true;
    });

    List<BluetoothService> services =
        await device.discoverServices();

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

    if (data.length < 2) return;

    int hr =
        (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];

    if (mounted && hr > 0) {

      setState(() {

        _heartRate = hr;

        if (_isWorkingOut) {

          _timeCounter += 1;

          _hrSpots.add(
              FlSpot(_timeCounter, _heartRate.toDouble()));

          if (_hrSpots.length > 50) {
            _hrSpots.removeAt(0);
          }

          _avgHeartRate =
              (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) /
                      _hrSpots.length)
                  .toInt();
        }
      });
    }
  }

  void _toggleWorkout() {

    setState(() {

      _isWorkingOut = !_isWorkingOut;

      if (_isWorkingOut) {

        _workoutTimer = Timer.periodic(
            const Duration(seconds: 1), (timer) {

          setState(() {

            _duration += const Duration(seconds: 1);

            if (_heartRate > 0) {
              _calories += 0.12;
            }

          });
        });

      } else {

        _workoutTimer?.cancel();
        _saveWorkout();
      }
    });
  }

  void _showToast(String msg) {

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));

  }

  Widget _dataRow(String l, String v) {

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Text(l),
          Text(v,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold))
        ],
      ),
    );
  }

  @override
  void dispose() {

    _scanSubscription?.cancel();
    _connectionSub?.cancel();
    _workoutTimer?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    double progress =
        (_calories / _goalCalories).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Indoor bike fit"),
        actions: [

          TextButton(
              onPressed: _showDeviceScanPopup,
              child: Text(
                  _isWatchConnected ? "연결됨" : "워치 연결",
                  style: const TextStyle(
                      color: Colors.greenAccent))),

          IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (c) =>
                          HistoryScreen(records: _records))))
        ],
      ),
      body: Column(
        children: [

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LineChart(
                LineChartData(
                  titlesData:
                      const FlTitlesData(show: false),
                  borderData:
                      FlBorderData(show: false),
                  gridData:
                      const FlGridData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                        spots: _hrSpots.isEmpty
                            ? [const FlSpot(0, 0)]
                            : _hrSpots,
                        isCurved: true,
                        dotData:
                            const FlDotData(show: false),
                        color: Colors.greenAccent)
                  ],
                ),
              ),
            ),
          ),

          _dataRow("심박수", "$_heartRate BPM"),
          _dataRow("평균", "$_avgHeartRate BPM"),
          _dataRow("칼로리",
              "${_calories.toStringAsFixed(1)} kcal"),

          _dataRow(
              "시간",
              "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}"),

          const SizedBox(height: 20),

          Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  color: Colors.greenAccent)),

          const SizedBox(height: 40),

          ElevatedButton(
              onPressed: _toggleWorkout,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _isWorkingOut
                      ? Colors.red
                      : Colors.green,
                  foregroundColor: Colors.white),
              child: Text(_isWorkingOut
                  ? "운동 종료 및 저장"
                  : "운동 시작")),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// 기록 화면
class HistoryScreen extends StatefulWidget {

  final List<WorkoutRecord> records;

  const HistoryScreen({Key? key, required this.records})
      : super(key: key);

  @override
  State<HistoryScreen> createState() =>
      _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {

    final dailyRecords = widget.records.where((r) {

      if (_selectedDay == null) return false;

      return r.date ==
          DateFormat('yyyy-MM-dd')
              .format(_selectedDay!);

    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록")),
      body: Column(
        children: [

          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,

            selectedDayPredicate: (day) =>
                isSameDay(_selectedDay, day),

            onDaySelected:
                (selectedDay, focusedDay) {

              setState(() {

                _selectedDay = selectedDay;
                _focusedDay = focusedDay;

              });
            },

            calendarStyle: const CalendarStyle(
              selectedDecoration: BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle),
              todayDecoration: BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle),
            ),
          ),

          const Divider(),

          Expanded(
            child: dailyRecords.isEmpty
                ? const Center(
                    child: Text("기록이 없습니다."))
                : ListView.builder(
                    itemCount: dailyRecords.length,
                    itemBuilder: (context, index) {

                      final r = dailyRecords[index];

                      return ListTile(
                        leading: const Icon(
                            Icons.directions_bike,
                            color: Colors.greenAccent),

                        title: Text(
                            "${r.calories.toInt()} kcal 소모"),

                        subtitle: Text(
                            "평균 ${r.avgHR} BPM / ${r.duration.inMinutes}분 운동"),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}
