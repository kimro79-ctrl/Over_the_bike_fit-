import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
  
  // 첫 프레임 이후 스플래시 제거 (블랙스크린 방지)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FlutterNativeSplash.remove();
  });
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
  String watchStatus = "워치 자동 검색 중...";
  List<FlSpot> heartRateSpots = [];
  static List<Map<String, dynamic>> workoutLogs = [];

  BluetoothDevice? connectedDevice;
  StreamSubscription? hrSubscription;
  StreamSubscription? scanSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    // 시작하자마자 권한 요청 및 워치 검색 시작
    _autoConnect();
  }

  @override
  void dispose() {
    hrSubscription?.cancel();
    scanSubscription?.cancel();
    workoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _autoConnect() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _startScan();
  }

  void _startScan() async {
    setState(() => watchStatus = "기기 검색 중...");
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        // Amazfit 또는 심박 서비스(180d)를 보유한 기기 자동 연결
        if (name.contains("watch") || name.contains("amazfit") || r.advertisementData.serviceUuids.contains(Guid("180d"))) {
          FlutterBluePlus.stopScan();
          _establishConnection(r.device);
          break;
        }
      }
    });
  }

  void _establishConnection(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      setState(() {
        connectedDevice = device;
        watchStatus = "연결됨: ${device.platformName}";
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid("180d")) {
          for (var c in s.characteristics) {
            if (c.uuid == Guid("2a37")) {
              await c.setNotifyValue(true);
              hrSubscription = c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    bpm = value[1];
                    heartRateSpots.add(FlSpot(heartRateSpots.length.toDouble(), bpm.toDouble()));
                    if (heartRateSpots.length > 100) heartRateSpots.removeAt(0);
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) {
      setState(() => watchStatus = "연결 실패 - 다시 탭");
    }
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
              const SizedBox(height: 20),
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: 3)),
              
              GestureDetector(
                onTap: _startScan,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(border: Border.all(color: neonColor), borderRadius: BorderRadius.circular(20)),
                  child: Text(watchStatus, style: const TextStyle(fontSize: 12, color: neonColor)),
                ),
              ),

              // 심박수 실시간 그래프 섹션
              Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(15)),
                child: Row(
                  children: [
                    Column(children: [
                      const Text("HEART RATE", style: TextStyle(fontSize: 10, color: Colors.white54)),
                      Text("${bpm > 0 ? bpm : '--'}", style: const TextStyle(fontSize: 35, fontWeight: FontWeight.bold, color: neonColor)),
                      const Text("BPM", style: TextStyle(fontSize: 12)),
                    ]),
                    const SizedBox(width: 20),
                    Expanded(
                      child: SizedBox(height: 60, child: LineChart(LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [LineChartBarData(
                          spots: heartRateSpots.isEmpty ? [const FlSpot(0, 0)] : heartRateSpots,
                          isCurved: true, color: neonColor, barWidth: 3, dotData: const FlDotData(show: false),
                        )]
                      ))),
                    )
                  ],
                ),
              ),

              const Spacer(),

              // 하단 컨트롤 (그라데이션 효과 적용)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.9)])
                ),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _infoCol("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                    _targetCol(),
                  ]),
                  const SizedBox(height: 30),
                  Row(children: [
                    _btn(isRunning ? "정지" : "시작", isRunning ? Colors.blueGrey : Colors.redAccent, () {
                      setState(() {
                        isRunning = !isRunning;
                        if (isRunning) {
                          workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                        } else {
                          workoutTimer?.cancel();
                        }
                      });
                    }),
                    const SizedBox(width: 10),
                    _btn("저장", Colors.green, () {
                      if (elapsedSeconds > 0) {
                        workoutLogs.add({
                          "date": "${DateTime.now().month}/${DateTime.now().day}",
                          "time": "${elapsedSeconds ~/ 60}분",
                          "maxBpm": "$bpm"
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("데이터가 저장되었습니다.")));
                      }
                    }),
                    const SizedBox(width: 10),
                    _btn("기록", Colors.blueGrey, () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryPage(logs: workoutLogs)));
                    }),
                  ]),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCol(String label, String val, Color col) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
    Text(val, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: col)),
  ]);

  Widget _targetCol() => Column(children: [
    const Text("목표설정", style: TextStyle(fontSize: 12, color: Colors.white70)),
    Row(children: [
      IconButton(onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }), icon: const Icon(Icons.remove_circle_outline)),
      Text("$targetMinutes분", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      IconButton(onPressed: () => setState(() => targetMinutes++), icon: const Icon(Icons.add_circle_outline)),
    ]),
  ]);

  Widget _btn(String txt, Color col, VoidCallback tap) => Expanded(
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: col, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      onPressed: tap, child: Text(txt, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
    ),
  );
}

class HistoryPage extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  const HistoryPage({super.key, required this.logs});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록"), backgroundColor: Colors.black),
      body: logs.isEmpty ? const Center(child: Text("기록이 없습니다.")) : ListView.builder(
        itemCount: logs.length,
        itemBuilder: (context, i) => ListTile(
          leading: const Icon(Icons.directions_bike, color: Color(0xFF00E5FF)),
          title: Text("${logs[i]['date']} 운동"),
          subtitle: Text("시간: ${logs[i]['time']} | 심박: ${logs[i]['maxBpm']} BPM"),
        ),
      ),
    );
  }
}
