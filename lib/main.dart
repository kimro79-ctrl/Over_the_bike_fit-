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
  List<FlSpot> _hrSpots = [];
  int _timerCount = 0;
  String _watchStatus = "워치 검색";
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _hrSubscription;

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
    setState(() => _watchStatus = "연결 시도...");
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
                    if (_hrSpots.length > 40) _hrSpots.removeAt(0);
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
                
                // 1. 워치 연결 상태 버튼
                GestureDetector(
                  onTap: _handleWatchSearch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                    ),
                    child: Text(_watchStatus, style: const TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                  ),
                ),

                const SizedBox(height: 20),

                // 2. 그래프 (워치연결 밑으로 배치, 크기 1/2 축소)
                SizedBox(
                  height: 70, // 높이를 기존의 절반 수준으로 축소
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(show: false),
                        titlesData: FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots,
                            isCurved: true,
                            color: Colors.cyanAccent.withOpacity(0.6),
                            barWidth: 2,
                            dotData: FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // 3. 데이터 배너 (더 어둡게 수정)
                _buildDarkPanel(
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

                // 4. 하단 버튼 (더 어둡게 + 터치 인식 수정)
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _actionButton(Icons.play_arrow, "시작", () => print("시작 눌림")),
                      const SizedBox(width: 30),
                      _actionButton(Icons.save, "저장", () => print("저장 눌림")),
                      const SizedBox(width: 30),
                      _actionButton(Icons.bar_chart, "기록", () => print("기록 눌림")),
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
      Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
    ],
  );

  // 배너를 더 어둡게 만드는 위젯
  Widget _buildDarkPanel({required Widget child}) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7), // 투명도를 낮추고 블랙을 강화 (더 어두움)
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: child,
    );
  }

  // 버튼을 더 어둡게 만들고 터치 영역을 확보하는 위젯
  Widget _actionButton(IconData i, String l, VoidCallback t) => Column(
    children: [
      Material( // InkWell 사용을 위해 Material 추가 (터치 피드백 강화)
        color: Colors.transparent,
        child: InkWell(
          onTap: t,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 65, height: 65,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6), // 버튼도 더 어둡게
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Center(child: Icon(i, size: 28, color: Colors.white.withOpacity(0.8))),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(l, style: const TextStyle(fontSize: 11, color: Colors.white30)),
    ],
  );
}
