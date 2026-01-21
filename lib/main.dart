import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());

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
  String watchStatus = "탭하여 워치 연결";
  List<FlSpot> heartRateSpots = [];
  List<Map<String, dynamic>> workoutLogs = [];

  BluetoothDevice? connectedDevice;
  StreamSubscription? hrSubscription;
  StreamSubscription? scanSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _setupBluetoothListener();
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedData = prefs.getString('workout_history');
    if (savedData != null) {
      setState(() {
        workoutLogs = List<Map<String, dynamic>>.from(json.decode(savedData));
      });
    }
  }

  Future<void> _saveLog(Map<String, dynamic> newLog) async {
    final prefs = await SharedPreferences.getInstance();
    workoutLogs.insert(0, newLog);
    await prefs.setString('workout_history', json.encode(workoutLogs));
    setState(() {});
  }

  void _setupBluetoothListener() {
    scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      if (connectedDevice != null) return;
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        // 갤럭시 워치(watch) 및 Amazfit 검색 강화
        if (name.contains("amazfit") || name.contains("watch") || r.advertisementData.serviceUuids.contains(Guid("180d"))) {
          await FlutterBluePlus.stopScan();
          _establishConnection(r.device);
          break;
        }
      }
    });
  }

  void _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    setState(() => watchStatus = "기기 검색 중...");
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      setState(() => watchStatus = "블루투스 확인 필요");
    }
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
              hrSubscription?.cancel();
              hrSubscription = c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    bpm = value[1];
                    heartRateSpots.add(FlSpot(heartRateSpots.length.toDouble(), bpm.toDouble()));
                    if (heartRateSpots.length > 80) heartRateSpots.removeAt(0);
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) {
      setState(() => watchStatus = "연결 실패: 재시도");
    }
  }

  // UI 헬퍼 위젯들
  Widget _infoBox(String label, String value, Color color) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color))
    ]);
  }

  Widget _targetBox() {
    return Column(children: [
      const Text("목표설정", style: TextStyle(fontSize: 11, color: Colors.grey)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }), icon: const Icon(Icons.remove_circle_outline)),
        Text("$targetMinutes분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        IconButton(onPressed: () => setState(() { targetMinutes++; }), icon: const Icon(Icons.add_circle_outline)),
      ])
    ]);
  }

  Widget _btn(String text, Color color, VoidCallback onTap) {
    return Expanded(child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      onPressed: onTap,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    const Color neonColor = Color(0xFF00E5FF);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover)),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 4, fontStyle: FontStyle.italic)),
              
              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(border: Border.all(color: connectedDevice != null ? neonColor : Colors.white24), borderRadius: BorderRadius.circular(20)),
                  child: Text(watchStatus, style: TextStyle(fontSize: 12, color: connectedDevice != null ? neonColor : Colors.white70)),
                ),
              ),

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(15), border: Border.all(color: neonColor.withOpacity(0.3))),
                child: Row(children: [
                  Column(children: [
                    const Text("HEART RATE", style: TextStyle(fontSize: 9, color: Colors.white54)),
                    Text("${bpm > 0 ? bpm : '--'}", style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold, color: neonColor)),
                  ]),
                  const SizedBox(width: 15),
                  Expanded(child: SizedBox(height: 50, child: LineChart(LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [LineChartBarData(spots: heartRateSpots.isEmpty ? [const FlSpot(0, 0)] : heartRateSpots, isCurved: true, color: neonColor, dotData: const FlDotData(show: false))],
                  )))),
                ]),
              ),

              const Spacer(),

              Container(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _infoBox("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                    _targetBox(),
                  ]),
                  const SizedBox(height: 20),
                  Row(children: [
                    _btn(isRunning ? "정지" : "시작", isRunning ? Colors.grey : Colors.redAccent, () {
                      setState(() {
                        isRunning = !isRunning;
                        if (isRunning) workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                        else workoutTimer?.cancel();
                      });
                    }),
                    const SizedBox(width: 10),
                    _btn("저장", Colors.green, () {
                      if (elapsedSeconds > 0) {
                        _saveLog({
                          "date": "${DateTime.now().year}.${DateTime.now().month}.${DateTime.now().day}",
                          "time": "${elapsedSeconds ~/ 60}분 ${elapsedSeconds % 60}초",
                          "maxBpm": "$bpm"
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록이 저장되었습니다")));
                      }
                    }),
                    const SizedBox(width: 10),
                    _btn("기록", Colors.blueGrey, () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryPage(logs: workoutLogs)));
                    }),
                  ]),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 15),
                child: Text("본 앱은 의료기기가 아니며 데이터는 참고용입니다.", style: TextStyle(fontSize: 9, color: Colors.white30)),
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
      body: logs.isEmpty ? const Center(child: Text("기록이 없습니다.")) : ListView.builder(
        itemCount: logs.length,
        itemBuilder: (context, index) => ListTile(
          leading: const Icon(Icons.history, color: Color(0xFF00E5FF)),
          title: Text("${logs[index]['date']} 운동"),
          subtitle: Text("시간: ${logs[index]['time']} | 심박수: ${logs[index]['maxBpm']} BPM"),
        ),
      ),
    );
  }
}
