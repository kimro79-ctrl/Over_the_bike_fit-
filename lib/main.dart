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
  // 스플래시 화면을 유지합니다.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
  
  // 앱 구동 후 2.5초 뒤에 스플래시 화면을 제거합니다.
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

  // 워치 스캔 로직 (에러 수정 및 최적화)
  void _startScan() async {
    // 권한 요청
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();

    setState(() => watchStatus = "워치 탐색 중...");
    
    try {
      // Screenshot_20260121_183722_Chrome.jpg의 에러 원인이었던 매개변수 수정
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      setState(() => watchStatus = "블루투스를 켜주세요");
      return;
    }

    scanSubscription?.cancel();
    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        // Amazfit 또는 심박수 서비스(180d)를 가진 기기 탐색
        if (name.contains("watch") || name.contains("fit") || name.contains("amazfit") || 
            r.advertisementData.serviceUuids.contains(Guid("180d"))) {
          
          FlutterBluePlus.stopScan();
          _establishConnection(r.device);
          break;
        }
      }
    });
  }

  void _establishConnection(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        connectedDevice = device;
        watchStatus = "연결됨: ${device.platformName}";
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid("180d")) { // 심박 서비스
          for (var c in s.characteristics) {
            if (c.uuid == Guid("2a37")) { // 심박 측정값
              await c.setNotifyValue(true);
              hrSubscription?.cancel();
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
      setState(() => watchStatus = "연결 실패");
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
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
              
              GestureDetector(
                onTap: _startScan,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: connectedDevice != null ? neonColor : Colors.white54),
                    borderRadius: BorderRadius.circular(20)
                  ),
                  child: Text(watchStatus, style: TextStyle(fontSize: 13, color: connectedDevice != null ? neonColor : Colors.white70)),
                ),
              ),

              // 심박수 차트
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(15)),
                child: Row(
                  children: [
                    Column(children: [
                      const Text("BPM", style: TextStyle(fontSize: 10, color: Colors.white54)),
                      Text("${bpm > 0 ? bpm : '--'}", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: neonColor)),
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

              // 컨트롤 패널
              Container(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.95)])
                ),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _info("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                    _target(),
                  ]),
                  const SizedBox(height: 30),
                  Row(children: [
                    _btn(isRunning ? "정지" : "시작", isRunning ? Colors.grey : Colors.redAccent, () {
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
                    _btn("저장", Colors.green, () async {
                      if (elapsedSeconds > 0) {
                        workoutLogs.insert(0, {
                          "date": "${DateTime.now().month}/${DateTime.now().day}",
                          "time": "${elapsedSeconds ~/ 60}분",
                          "maxBpm": "$bpm"
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('workoutLogs', jsonEncode(workoutLogs));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록이 저장되었습니다.")));
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

  Widget _info(String t, String v, Color c) => Column(children: [Text(t, style: const TextStyle(fontSize: 12)), Text(v, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: c))]);
  
  Widget _target() => Column(children: [
    const Text("목표설정", style: TextStyle(fontSize: 12)),
    Row(children: [
      IconButton(onPressed: () => setState(() => targetMinutes--), icon: const Icon(Icons.remove_circle_outline)),
      Text("$targetMinutes분", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      IconButton(onPressed: () => setState(() => targetMinutes++), icon: const Icon(Icons.add_circle_outline)),
    ])
  ]);

  Widget _btn(String t, Color c, VoidCallback f) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: f, child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold))));
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
