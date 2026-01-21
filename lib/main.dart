import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
  await Future.delayed(const Duration(milliseconds: 2500));
  FlutterNativeSplash.remove();
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
  List<Map<String, dynamic>> workoutLogs = [];
  double totalCalories = 0.0;

  BluetoothDevice? connectedDevice;
  StreamSubscription? hrSubscription;
  StreamSubscription? scanSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('workoutLogs');
    if (data != null) {
      setState(() => workoutLogs = List<Map<String, dynamic>>.from(jsonDecode(data)));
    }
  }

  // 심박수 85 이상일 때만 칼로리 계산 (정지 상태 상승 방지)
  double _calculateCalories(int currentBpm) {
    if (currentBpm < 85) return 0.0;
    return (currentBpm - 70) * 0.0016; 
  }

  void _startScan() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    setState(() => watchStatus = "워치 탐색 중...");
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      setState(() => watchStatus = "블루투스 확인 필요");
      return;
    }
    scanSubscription?.cancel();
    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        if (name.contains("watch") || name.contains("fit") || name.contains("amazfit") || 
            r.advertisementData.serviceUuids.contains(Guid("180d"))) {
          FlutterBluePlus.stopScan();
          _connectToDevice(r.device);
          break;
        }
      }
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() { connectedDevice = device; watchStatus = "연결됨: ${device.platformName}"; });
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
                    if (heartRateSpots.length > 50) heartRateSpots.removeAt(0);
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) { setState(() => watchStatus = "연결 실패"); }
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
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
              
              GestureDetector(
                onTap: _startScan,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(border: Border.all(color: neonColor.withOpacity(0.5)), borderRadius: BorderRadius.circular(15)),
                  child: Text(watchStatus, style: const TextStyle(fontSize: 9, color: neonColor)),
                ),
              ),

              // 심박수 영역 (콤팩트 축소)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 5),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(15)),
                child: Row(
                  children: [
                    Column(children: [
                      const Text("BPM", style: TextStyle(fontSize: 9, color: Colors.white54)),
                      Text("${bpm > 0 ? bpm : '--'}", style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: neonColor)),
                    ]),
                    const SizedBox(width: 20),
                    Expanded(
                      child: SizedBox(height: 35, child: LineChart(LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [LineChartBarData(
                          spots: heartRateSpots.isEmpty ? [const FlSpot(0, 0)] : heartRateSpots,
                          isCurved: true, color: neonColor, barWidth: 2, dotData: const FlDotData(show: false),
                        )]
                      ))),
                    )
                  ],
                ),
              ),

              const Spacer(),

              // 하단 일렬 레이아웃 (칼로리 | 운동시간 | 목표설정)
              Container(
                padding: const EdgeInsets.fromLTRB(15, 20, 15, 30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.95)])
                ),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _item("칼로리", "${totalCalories.toStringAsFixed(1)} kcal", neonColor),
                      _divider(),
                      _item("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.white),
                      _divider(),
                      _targetItem(),
                    ],
                  ),
                  const SizedBox(height: 25),
                  Row(children: [
                    _btn(isRunning ? "정지" : "시작", isRunning ? Colors.grey : Colors.redAccent, () {
                      setState(() {
                        isRunning = !isRunning;
                        if (isRunning) {
                          workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                            setState(() {
                              elapsedSeconds++;
                              if (bpm >= 85) totalCalories += _calculateCalories(bpm);
                            });
                          });
                        } else { workoutTimer?.cancel(); }
                      });
                    }),
                    const SizedBox(width: 8),
                    _btn("저장", Colors.green, () async {
                      if (elapsedSeconds > 0) {
                        workoutLogs.insert(0, {
                          "date": "${DateTime.now().month}/${DateTime.now().day}",
                          "time": "${elapsedSeconds ~/ 60}분",
                          "avgBpm": "$bpm",
                          "kcal": totalCalories.toStringAsFixed(1)
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('workoutLogs', jsonEncode(workoutLogs));
                        setState(() { elapsedSeconds = 0; totalCalories = 0.0; heartRateSpots.clear(); isRunning = false; });
                        workoutTimer?.cancel();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록 저장됨")));
                      }
                    }),
                    const SizedBox(width: 8),
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

  Widget _item(String label, String value, Color color) => Expanded(child: Column(children: [
    Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
    const SizedBox(height: 4),
    Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
  ]));

  Widget _targetItem() => Expanded(child: Column(children: [
    const Text("목표설정", style: TextStyle(fontSize: 9, color: Colors.white54)),
    const SizedBox(height: 2),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      GestureDetector(onTap: () => setState(() => targetMinutes--), child: const Icon(Icons.remove, size: 14)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text("$targetMinutes분", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
      GestureDetector(onTap: () => setState(() => targetMinutes++), child: const Icon(Icons.add, size: 14)),
    ])
  ]));

  Widget _divider() => Container(width: 1, height: 20, color: Colors.white10);

  Widget _btn(String t, Color c, VoidCallback f) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: f, child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))));
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
          title: Text("${logs[i]['date']} 운동 - ${logs[i]['kcal']} kcal"),
          subtitle: Text("시간: ${logs[i]['time']} | 심박: ${logs[i]['avgBpm']} BPM"),
        ),
      ),
    );
  }
}
