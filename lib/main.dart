import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(const BikeFitApp());

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
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
  List<FlSpot> _hrSpots = [];
  int _timerCount = 0;
  String _watchStatus = "워치 검색";
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _hrSubscription;

  // 워치 검색 및 연결
  Future<void> _handleWatchSearch() async {
    print("검색 버튼 눌림");
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
              await c.setNotifyValue(true); 
              _hrSubscription = c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    _heartRate = value[1]; 
                    if (_hrSpots.length > 30) _hrSpots.removeAt(0);
                    _hrSpots.add(FlSpot(_timerCount.toDouble(), _heartRate.toDouble()));
                    _timerCount++;
                    double sum = _hrSpots.map((e) => e.y).reduce((a, b) => a + b);
                    _avgHeartRate = (sum / _hrSpots.length).round();
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) { setState(() => _watchStatus = "연결 실패"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 배경 이미지
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover)),
          
          // 2. 실제 콘텐츠
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 10),
                
                // 워치 검색 (터치가 확실한 ElevatedButton 사용)
                Center(
                  child: ElevatedButton(
                    onPressed: _handleWatchSearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.8),
                      side: const BorderSide(color: Colors.cyanAccent, width: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text(_watchStatus, style: const TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                  ),
                ),

                const SizedBox(height: 10),

                // 그래프 (크기 축소 및 위치 조정)
                SizedBox(
                  height: 60,
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 50),
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
                            barWidth: 2,
                            dotData: FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // 데이터 배너 (요청대로 더 어둡게)
                Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  padding: const EdgeInsets.symmetric(vertical: 25),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.9), // 매우 어둡게
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataTile("실시간", "$_heartRate", Colors.cyanAccent),
                      _dataTile("평균", "$_avgHeartRate", Colors.redAccent),
                      _dataTile("칼로리", "0.0", Colors.orangeAccent),
                      _dataTile("시간", "00:00", Colors.blueAccent),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // 하단 버튼부 (동작 문제를 위해 최상단 노출 및 InkWell 적용)
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _actionButton(Icons.play_arrow, "시작", () => print("START 버튼 작동")),
                      const SizedBox(width: 30),
                      _actionButton(Icons.save, "저장", () => print("SAVE 버튼 작동")),
                      const SizedBox(width: 30),
                      _actionButton(Icons.bar_chart, "기록", () => print("LOG 버튼 작동")),
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

  Widget _dataTile(String l, String v, Color c) => Column(
    children: [
      Text(l, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
    ],
  );

  Widget _actionButton(IconData i, String l, VoidCallback t) => Column(
    children: [
      // InkWell과 Material 조합으로 터치 영역 및 피드백 보장
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: t,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 65, height: 65,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85), // 매우 어둡게
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Icon(i, size: 28, color: Colors.white),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(l, style: const TextStyle(fontSize: 11, color: Colors.white38)),
    ],
  );
}
