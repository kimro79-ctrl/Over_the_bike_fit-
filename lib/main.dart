import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BikeFitApp());
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
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
  // BLE 및 데이터 변수
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  DiscoveredDevice? _device;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _hrStream;

  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  int _heartRate = 0;
  int _avgHeartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _timer;

  List<int> _hrHistory = [];
  List<FlSpot> _hrSpots = [const FlSpot(0, 0)];
  double _graphX = 0;

  // UUID (BLE Heart Rate Service)
  final Uuid heartRateService =
      Uuid.parse("0000180D-0000-1000-8000-00805f9b34fb");
  final Uuid heartRateChar =
      Uuid.parse("00002A37-0000-1000-8000-00805f9b34fb");

  // 워치 연결
  Future<void> _connectWatch() async {
    if (await Permission.bluetoothScan.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted) {
      setState(() => _isWatchConnected = false);

      // 스캔 시작
      _ble.scanForDevices(withServices: []).listen((device) {
        if (device.name.contains("GTS2 mini")) {
          _device = device;
          _ble.stopScan();

          // 연결 시도
          _connection = _ble
              .connectToDevice(id: device.id, connectionTimeout: const Duration(seconds: 10))
              .listen((update) {
            if (update.connectionState == DeviceConnectionState.connected) {
              setState(() => _isWatchConnected = true);
              _listenHeartRate();
            }
          });
        }
      });
    }
  }

  // 실시간 심박수 수신
  void _listenHeartRate() {
    if (_device == null) return;

    final characteristic = QualifiedCharacteristic(
      serviceId: heartRateService,
      characteristicId: heartRateChar,
      deviceId: _device!.id,
    );

    _hrStream = _ble.subscribeToCharacteristic(characteristic).listen((data) {
      if (data.isNotEmpty) {
        final hr = data.length > 1 ? data[1] : data[0];
        setState(() {
          _heartRate = hr;
          _hrHistory.add(hr);
          _avgHeartRate =
              (_hrHistory.reduce((a, b) => a + b) / _hrHistory.length).round();
          _calories += 0.12;
          _graphX += 1;
          _hrSpots.add(FlSpot(_graphX, hr.toDouble()));
          if (_hrSpots.length > 40) _hrSpots.removeAt(0);
        });
      }
    });
  }

  // 운동 시작/중지
  void _toggleWorkout() {
    if (_isWorkingOut) {
      _timer?.cancel();
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _duration += const Duration(seconds: 1);
        });
      });
    }
    setState(() => _isWorkingOut = !_isWorkingOut);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connection?.cancel();
    _hrStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 배경 이미지
          Positioned.fill(
            child: Opacity(
              opacity: 0.6,
              child: Image.asset('assets/background.png', fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: Colors.blueGrey.withOpacity(0.1))),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                const Text('Over The Bike Fit',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70)),

                const SizedBox(height: 15),

                // 워치 연결 버튼
                GestureDetector(
                  onTap: _connectWatch,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                          color: _isWatchConnected
                              ? Colors.cyanAccent
                              : Colors.white24),
                      color: Colors.black54,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth,
                            size: 14,
                            color: _isWatchConnected
                                ? Colors.cyanAccent
                                : Colors.white),
                        const SizedBox(width: 6),
                        Text(
                            _isWatchConnected
                                ? "Amazfit GTS2 mini"
                                : "워치 연결하기",
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // 심박 그래프
                SizedBox(
                  height: 60,
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: _isWatchConnected
                      ? LineChart(_lineChartData())
                      : const Center(
                          child: Text("연결 대기 중...",
                              style:
                                  TextStyle(color: Colors.white24, fontSize: 10))),
                ),

                const Spacer(),

                // 데이터 패널
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.black.withOpacity(0.7),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataItem("심박수",
                          _isWatchConnected ? "$_heartRate" : "-", Colors.cyanAccent),
                      _dataItem("심박수평균",
                          _isWatchConnected ? "$_avgHeartRate" : "-", Colors.redAccent),
                      _dataItem("칼로리", _calories.toStringAsFixed(1),
                          Colors.orangeAccent),
                      _dataItem("운동시간", _formatDuration(_duration),
                          Colors.blueAccent),
                    ],
                  ),
                ),

                // 하단 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionBtn(
                          _isWorkingOut
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          "중지",
                          _toggleWorkout,
                          Colors.orangeAccent),
                      _actionBtn(Icons.save_rounded, "저장", () {}, Colors.white),
                      _actionBtn(
                          Icons.leaderboard_rounded, "기록", () {}, Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataItem(String label, String value, Color color) => Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _actionBtn(
          IconData icon, String label, VoidCallback onTap, Color color) =>
      Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(icon, size: 30, color: color),
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ],
      );

  LineChartData _lineChartData() {
    return LineChartData(
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: _hrSpots,
          isCurved: true,
          color: Colors.cyanAccent,
          barWidth: 1.5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
              show: true, color: Colors.cyanAccent.withOpacity(0.1)),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) =>
      "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
