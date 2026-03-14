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

class AssetSplashScreen extends StatefulWidget {
  const AssetSplashScreen({Key? key}) : super(key: key);

  @override
  _AssetSplashScreenState createState() => _AssetSplashScreenState();
}

class _AssetSplashScreenState extends State<AssetSplashScreen> {
  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() async {
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => const WorkoutScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Image.asset(
          'assets/splash/splash_screen.png',
          width: MediaQuery.of(context).size.width,
          fit: BoxFit.contain,
          errorBuilder: (c, e, s) => const Text("BIKE FIT",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold)),
        ),
      ),
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

  bool _isWorkingOut = false;
  bool _isWatchConnected = false;

  bool _isScanning = false;

  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;

  List<WorkoutRecord> _records = [];

  List<ScanResult> _filteredResults = [];

  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestAllPermissions();
    });
  }

  Future<void> _requestAllPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.locationWhenInUse,
      Permission.sensors,
    ].request();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;

      final String? res = prefs.getString('workout_records');

      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);

        _records = decoded
            .map((item) => WorkoutRecord(
                item['id'] ?? DateTime.now().toString(),
                item['date'],
                item['avgHR'],
                (item['calories'] as num).toDouble(),
                Duration(seconds: item['durationSeconds'] ?? 0)))
            .toList();
      }
    });
  }

  void _showDeviceScanPopup() async {

    await _requestAllPermissions();

    if (_isWatchConnected) return;

    if (_isScanning) return;

    if (await FlutterBluePlus.isOn == false) {
      _showToast("블루투스를 켜주세요");
      return;
    }

    _isScanning = true;

    _filteredResults.clear();

    try {
      await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15));
    } catch (e) {
      _showToast("블루투스 스캔 실패");
      _isScanning = false;
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) =>
          StatefulBuilder(builder: (context, setModalState) {

        _scanSubscription =
            FlutterBluePlus.onScanResults.listen((results) {

          if (mounted) {

            setModalState(() {

              _filteredResults = results.where((r) {

                final name = r.device.platformName;
                final adv = r.advertisementData.advName;

                return name.isNotEmpty || adv.isNotEmpty;

              }).toList();
            });
          }
        });

        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.4,
          child: Column(children: [

            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),

            const SizedBox(height: 20),

            const Text("연결할 워치 선택",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),

            const SizedBox(height: 10),

            Expanded(
              child: _filteredResults.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Colors.greenAccent))
                  : ListView.builder(
                      itemCount: _filteredResults.length,
                      itemBuilder: (context, index) {

                        final d = _filteredResults[index];

                        final name =
                            d.device.platformName.isNotEmpty
                                ? d.device.platformName
                                : d.advertisementData.advName;

                        return ListTile(
                          leading: const Icon(Icons.watch,
                              color: Colors.blueAccent),
                          title: Text(name,
                              style: const TextStyle(
                                  color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            _connectToDevice(d.device);
                          },
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
      _isScanning = false;
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _setupDevice(device);
    } catch (e) {
      _showToast("연결 실패");
    }
  }

  void _setupDevice(BluetoothDevice device) async {
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
    if (data.isEmpty) return;

    int hr =
        (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];

    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;

        if (_isWorkingOut) {
          _timeCounter += 1;

          _hrSpots.add(FlSpot(
              _timeCounter, _heartRate.toDouble()));

          if (_hrSpots.length > 50) {
            _hrSpots.removeAt(0);
          }

          _avgHeartRate = (_hrSpots
                      .map((e) => e.y)
                      .reduce((a, b) => a + b) /
                  _hrSpots.length)
              .toInt();
        }
      });
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)));
  }

  Widget _statItem(String l, String v, Color c) =>
      Column(children: [
        Text(l,
            style: const TextStyle(
                fontSize: 10, color: Colors.white60)),
        const SizedBox(height: 6),
        Text(v,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: c))
      ]);

  String _formatDuration(Duration d) =>
      "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [

        Positioned.fill(
            child: Opacity(
                opacity: 0.8,
                child: Image.asset('assets/background.png',
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                        Container(color: Colors.black)))),

        SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [

              const SizedBox(height: 40),

              Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [

                    const Text('Indoor bike fit',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),

                    GestureDetector(
                        onTap: _showDeviceScanPopup,
                        child: Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6),
                            decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                        Colors.greenAccent)),
                            child: Text(
                                _isWatchConnected
                                    ? "연결됨"
                                    : "워치 연결",
                                style: const TextStyle(
                                    color:
                                        Colors.greenAccent,
                                    fontSize: 10))))
                  ]),

              const SizedBox(height: 40),

              SizedBox(
                  height: 80,
                  child: LineChart(LineChartData(
                      gridData:
                          const FlGridData(show: false),
                      titlesData:
                          const FlTitlesData(show: false),
                      borderData:
                          FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                            spots: _hrSpots.isEmpty
                                ? [const FlSpot(0, 0)]
                                : _hrSpots,
                            isCurved: true,
                            color: Colors.greenAccent,
                            barWidth: 3,
                            dotData:
                                const FlDotData(show: false))
                      ]))),

              const Spacer(),

              Container(
                  padding:
                      const EdgeInsets.symmetric(
                          vertical: 20),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius:
                          BorderRadius.circular(20)),
                  child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceEvenly,
                      children: [
                        _statItem("심박수", "$_heartRate",
                            Colors.greenAccent),
                        _statItem("평균",
                            "$_avgHeartRate",
                            Colors.redAccent),
                        _statItem(
                            "칼로리",
                            _calories
                                .toStringAsFixed(1),
                            Colors.orangeAccent),
                        _statItem("시간",
                            _formatDuration(_duration),
                            Colors.blueAccent)
                      ])),

              const SizedBox(height: 30),

              _controlButtons(),

              const SizedBox(height: 40)
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _controlButtons() => Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [

        _actionBtn(
            _isWorkingOut
                ? Icons.pause
                : Icons.play_arrow,
            "시작", () {

          setState(() {

            _isWorkingOut = !_isWorkingOut;

            if (_isWorkingOut) {

              _workoutTimer = Timer.periodic(
                  const Duration(seconds: 1),
                  (t) {

                setState(() {

                  _duration +=
                      const Duration(seconds: 1);

                  if (_heartRate >= 95) {
                    _calories += 0.15;
                  }

                });
              });

            } else {

              _workoutTimer?.cancel();

            }
          });
        }),

        const SizedBox(width: 20),

        _actionBtn(Icons.refresh, "리셋", () {

          setState(() {

            _duration = Duration.zero;
            _calories = 0.0;
            _heartRate = 0;
            _hrSpots = [];

          });
        }),

        const SizedBox(width: 20),

        _actionBtn(Icons.save, "저장", () async {

          final newRec = WorkoutRecord(
              DateTime.now().toString(),
              DateFormat('yyyy-MM-dd')
                  .format(DateTime.now()),
              _avgHeartRate,
              _calories,
              _duration);

          _records.insert(0, newRec);

          final prefs =
              await SharedPreferences.getInstance();

          await prefs.setString(
              'workout_records',
              jsonEncode(_records
                  .map((r) => r.toJson())
                  .toList()));

          _showToast("저장 완료");
        }),

        const SizedBox(width: 20),

        _actionBtn(Icons.calendar_month, "기록", () {

          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (c) => HistoryScreen(
                      records: _records,
                      onSync: _loadInitialData)));
        }),
      ]);

  Widget _actionBtn(
          IconData i, String l, VoidCallback t) =>
      Column(children: [
        IconButton(
            icon: Icon(i,
                color: Colors.white, size: 30),
            onPressed: t),
        Text(l,
            style: const TextStyle(
                fontSize: 10,
                color: Colors.white70))
      ]);
}

class HistoryScreen extends StatelessWidget {

  final List<WorkoutRecord> records;
  final VoidCallback onSync;

  const HistoryScreen(
      {Key? key,
      required this.records,
      required this.onSync})
      : super(key: key);

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록")),
      body: ListView.builder(
        itemCount: records.length,
        itemBuilder: (context, index) {

          final r = records[index];

          return ListTile(
            leading:
                const Icon(Icons.directions_bike),
            title:
                Text("${r.calories.toInt()} kcal 소모"),
            subtitle:
                Text("${r.date} / ${r.duration.inMinutes}분"),
            trailing: Text("${r.avgHR} BPM"),
          );
        },
      ),
    );
  }
}
