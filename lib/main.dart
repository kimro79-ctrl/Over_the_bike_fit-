import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});
  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int bpm = 0;
  int targetMinutes = 20;
  int elapsedSeconds = 0;
  bool isRunning = false;
  String watchStatus = "탭하여 워치 연결";
  List<FlSpot> heartRateSpots = [];
  static List<Map<String, dynamic>> workoutLogs = [];

  BluetoothDevice? connectedDevice;
  StreamSubscription? hrSubscription;
  StreamSubscription? scanSubscription;
  StreamSubscription? connectionSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () => FlutterNativeSplash.remove());
    _setupBluetoothListener();
  }

  @override
  void dispose() {
    hrSubscription?.cancel();
    scanSubscription?.cancel();
    connectionSubscription?.cancel();
    workoutTimer?.cancel();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (statuses[Permission.bluetoothScan]!.isDenied ||
        statuses[Permission.bluetoothConnect]!.isDenied) {
      await openAppSettings();
      return false;
    }
    return true;
  }

  void _setupBluetoothListener() {
    scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      if (connectedDevice != null) return;

      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        if (name.contains("amazfit") || r.advertisementData.serviceUuids.contains(Guid("180d"))) {
          await FlutterBluePlus.stopScan();
          _establishConnection(r.device);
          break;
        }
      }
    }, onError: (e) {
      setState(() => watchStatus = "스캔 오류: Bluetooth 확인");
    });
  }

  void _connectWatch() async {
    bool permsGranted = await _requestPermissions();
    if (!permsGranted) {
      setState(() => watchStatus = "권한 필요 – 설정에서 허용");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bluetooth 권한을 허용해주세요")),
      );
      return;
    }

    setState(() => watchStatus = "기기 검색 중...");
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    } catch (e) {
      setState(() => watchStatus = "스캔 실패: Bluetooth 켜기");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Bluetooth를 켜주세요: $e")),
      );
    }
  }

  void _establishConnection(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      setState(() {
        connectedDevice = device;
        watchStatus = "연결됨: ${device.platformName}";
      });

      connectionSubscription?.cancel();
      connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            watchStatus = "연결 끊김 – 재연결 탭";
            bpm = 0;
            heartRateSpots.clear();
          });
          hrSubscription?.cancel();
          connectedDevice = null;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("심박 센서 연결이 끊겼습니다")),
          );
        }
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid("180d")) {
          for (var c in s.characteristics) {
            if (c.uuid == Guid("2a37")) {
              await c.setNotifyValue(true);
              hrSubscription?.cancel();
              hrSubscription = c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    bpm = value[1];
                    heartRateSpots.add(FlSpot(heartRateSpots.length.toDouble(), bpm.toDouble()));
                    if (heartRateSpots.length > 120) heartRateSpots.removeAt(0);
                  });
                }
              });
              break;
            }
          }
        }
      }
    } catch (e) {
      setState(() => watchStatus = "연결 실패: 재시도");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("연결 실패: $e")),
      );
    }
  }

  Widget _infoBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color))
      ],
    );
  }

  Widget _targetBox() {
    return Column(
      children: [
        const Text("목표설정", style: TextStyle(fontSize: 11, color: Colors.grey)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }),
              icon: const Icon(Icons.remove_circle_outline, size: 20),
            ),
            Text("$targetMinutes분", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            IconButton(
              onPressed: () => setState(() { targetMinutes++; }),
              icon: const Icon(Icons.add_circle_outline, size: 20),
            ),
          ],
        )
      ],
    );
  }

  Widget _btn(String text, Color color, VoidCallback onTap) {
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color neonColor = Color(0xFF00E5FF);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Text(
                "OVER THE BIKE FIT",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 4, fontStyle: FontStyle.italic),
              ),

              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: connectedDevice != null ? neonColor : Colors.white24),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    watchStatus,
                    style: TextStyle(fontSize: 11, color: connectedDevice != null ? neonColor : Colors.white70),
                  ),
                ),
              ),

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 5),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: neonColor.withOpacity(0.3), width: 1),
                ),
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("HEART RATE", style: TextStyle(color: neonColor.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.bold)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text("${bpm > 0 ? bpm : '--'}", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: neonColor)),
                            const SizedBox(width: 4),
                            const Text("BPM", style: TextStyle(fontSize: 10, color: Colors.white70)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: SizedBox(
                        height: 45,
                        child: LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: false),
                            titlesData: const FlTitlesData(show: false),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: heartRateSpots.isEmpty ? [const FlSpot(0, 0)] : heartRateSpots,
                                isCurved: true,
                                color: neonColor,
                                barWidth: 2,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: true, color: neonColor.withOpacity(0.1)),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              Container(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _infoBox("운동시간", "\( {(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}: \){(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                        _targetBox(),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Row(
                        children: [
                          _btn(
                            isRunning ? "정지" : "시작",
                            isRunning ? Colors.grey : Colors.redAccent,
                            () {
                              setState(() {
                                isRunning = !isRunning;
                                if (isRunning) {
                                  workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                                } else {
                                  workoutTimer?.cancel();
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          _btn("저장", Colors.green, () {
                            if (elapsedSeconds > 0) {
                              int maxBpm = heartRateSpots.isNotEmpty
                                  ? heartRateSpots.map((e) => e.y.toInt()).reduce((a, b) => a > b ? a : b)
                                  : bpm;
                              workoutLogs.add({
                                "date": "\( {DateTime.now().month}/ \){DateTime.now().day}",
                                "time": "${elapsedSeconds ~/ 60}분",
                                "maxBpm": "$maxBpm"
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("운동 데이터 저장 완료")),
                              );
                            }
                          }),
                          const SizedBox(width: 8),
                          _btn("기록", Colors.blueGrey, () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => HistoryPage(logs: workoutLogs)),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  const HistoryPage({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록"), backgroundColor: Colors.black),
      body: logs.isEmpty
          ? const Center(child: Text("아직 기록이 없습니다."))
          : ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) => ListTile(
                leading: const Icon(Icons.directions_bike, color: Color(0xFF00E5FF)),
                title: Text("${logs[index]['date']} 운동"),
                subtitle: Text("시간: ${logs[index]['time']} | 최고 심박수: ${logs[index]['maxBpm']} BPM"),
              ),
            ),
    );
  }
}
