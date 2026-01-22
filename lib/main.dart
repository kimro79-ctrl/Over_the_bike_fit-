import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:ui';

void main() => runApp(const BikeFitApp());

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
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
  int _heartRate = 0;
  int _avgHeartRate = 0;
  List<FlSpot> _hrSpots = []; // 그래프용 데이터 포인트
  int _timerCount = 0;
  String _watchStatus = "워치 검색";
  bool _isWorkingOut = false;
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _hrSubscription;

  // 권한 및 워치 검색
  Future<void> _handleWatchSearch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _startScanning();
  }

  void _startScanning() async {
    setState(() => _watchStatus = "검색 중...");
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        if (name.contains("amazfit") || name.contains("watch") || name.contains("gts")) {
          FlutterBluePlus.stopScan();
          _connectToDevice(r.device);
          break;
        }
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() => _watchStatus = "연결 중...");
    try {
      await device.connect();
      _connectedDevice = device;
      setState(() => _watchStatus = "연결됨: ${device.platformName}");

      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid.toString().contains("180d")) {
          for (var c in s.characteristics) {
            if (c.uuid.toString().contains("2a37")) {
              await c.setNotify(true);
              _hrSubscription = c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    _heartRate = value[1];
                    // 그래프 데이터 추가 (최대 30개 유지)
                    if (_hrSpots.length > 30) _hrSpots.removeAt(0);
                    _hrSpots.add(FlSpot(_timerCount.toDouble(), _heartRate.toDouble()));
                    _timerCount++;
                    
                    // 평균 심박수 계산
                    double sum = _hrSpots.map((e) => e.y).reduce((a, b) => a + b);
                    _avgHeartRate = (sum / _hrSpots.length).round();
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) {
      setState(() => _watchStatus = "연결 실패");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover)),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                
                const SizedBox(height: 15),
                GestureDetector(
                  onTap: _handleWatchSearch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                    ),
                    child: Text(_watchStatus, style: const TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                  ),
                ),

                const Spacer(),

                // 실시간 그래프 섹션
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(show: false),
                      titlesData: FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots,
                          isCurved: true,
                          color: Colors.cyanAccent,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 데이터 배너 (초투명 유리 효과)
                _glassCard(
                  width: MediaQuery.of(context).size.width * 0.9,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataCell("실시간", "$_heartRate", Colors.cyanAccent),
                      _dataCell("평균", "$_avgHeartRate", Colors.redAccent),
                      _dataCell("칼로리", "0.0", Colors.orangeAccent),
                      _dataCell("시간", "00:00", Colors.blueAccent),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // 버튼부 (터치 100% 인식 구조)
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _actionButton(Icons.play_arrow, "시작", () => setState(() => _isWorkingOut = !_isWorkingOut)),
                      const SizedBox(width: 25),
                      _actionButton(Icons.save, "저장", () {}),
                      const SizedBox(width: 25),
                      _actionButton(Icons.bar_chart, "기록", () {}),
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _dataCell(String l, String v, Color c) => Column(
    children: [
      Text(l, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
    ],
  );

  Widget _glassCard({required double width, required Widget child}) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02), // 아주 투명하게
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(padding: const EdgeInsets.all(25), child: child),
        ),
      ),
    );
  }

  Widget _actionButton(IconData i, String l, VoidCallback t) => Column(
    children: [
      GestureDetector(
        onTap: t,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 65, height: 65,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03), // 초투명
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Center(child: Icon(i, size: 28, color: Colors.white)),
        ),
      ),
      const SizedBox(height: 10),
      Text(l, style: const TextStyle(fontSize: 11, color: Colors.white38)),
    ],
  );
}
