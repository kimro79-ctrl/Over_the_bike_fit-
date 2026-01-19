import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
  List<double> heartPoints = List.generate(45, (index) => 0.0);
  static List<Map<String, String>> workoutLogs = []; // 기록 저장용
  
  BluetoothDevice? connectedDevice;
  StreamSubscription? hrSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () => FlutterNativeSplash.remove());
  }

  // 워치 연동 강화: 갤럭시, 어메이즈핏 등 범용 스캔
  void _connectWatch() async {
    setState(() => watchStatus = "워치 찾는 중...");
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        // 이름이 있거나 심박수 서비스(180d)가 포함된 기기 자동 연결
        if (connectedDevice == null && (r.device.platformName.isNotEmpty || r.advertisementData.serviceUuids.contains(Guid("180d")))) {
          await FlutterBluePlus.stopScan();
          _establishConnection(r.device);
          break;
        }
      }
    });
  }

  void _establishConnection(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() { connectedDevice = device; watchStatus = "${device.platformName} 연결됨"; });
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
                    heartPoints.add(bpm.toDouble());
                    heartPoints.removeAt(0);
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) { setState(() => watchStatus = "연결 실패: 재시도"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover)),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(colors: [Colors.white, Colors.redAccent]).createShader(bounds),
                child: const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 6, fontStyle: FontStyle.italic)),
              ),
              
              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.only(top: 15),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), border: Border.all(color: connectedDevice != null ? Colors.greenAccent : Colors.redAccent.withOpacity(0.5)), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.watch, size: 14, color: connectedDevice != null ? Colors.greenAccent : Colors.grey),
                    const SizedBox(width: 8),
                    Text(watchStatus, style: TextStyle(fontSize: 11, color: connectedDevice != null ? Colors.greenAccent : Colors.white)),
                  ]),
                ),
              ),

              const Spacer(),
              // [중앙부] 희미한 이미지 제거 및 심박수 강조
              if (bpm > 0) ...[
                Text("$bpm", style: const TextStyle(fontSize: 100, fontWeight: FontWeight.bold)),
                const Text("BPM", style: TextStyle(color: Colors.redAccent, letterSpacing: 5)),
                const SizedBox(height: 20),
                SizedBox(height: 50, width: 200, child: CustomPaint(painter: MiniNeonPainter(heartPoints))),
              ] else ...[
                const Icon(Icons.favorite_border, size: 80, color: Colors.white10),
                const SizedBox(height: 10),
                const Text("WAITING FOR DATA", style: TextStyle(color: Colors.white24, letterSpacing: 2)),
              ],
              const Spacer(),

              // 정보 섹션 (시간 조정 버튼 포함)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  statUnit("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                  Column(
                    children: [
                      const Text("목표시간", style: TextStyle(color: Colors.grey, fontSize: 10)),
                      Row(children: [
                        IconButton(onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }), icon: const Icon(Icons.remove_circle_outline, size: 20)),
                        Text("$targetMinutes분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        IconButton(onPressed: () => setState(() { targetMinutes++; }), icon: const Icon(Icons.add_circle_outline, size: 20)),
                      ]),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // 하단 버튼 3등분
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 50),
                child: Row(children: [
                  actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent, () {
                    setState(() { isRunning = !isRunning; if (isRunning) workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++)); else workoutTimer?.cancel(); });
                  }),
                  const SizedBox(width: 10),
                  actionBtn("저장", Colors.green.withOpacity(0.7), () {
                    if (elapsedSeconds > 0) {
                      workoutLogs.add({"date": "${DateTime.now().month}/${DateTime.now().day}", "time": "${elapsedSeconds ~/ 60}분", "bpm": "$bpm"});
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 데이터가 저장되었습니다.")));
                      setState(() { isRunning = false; workoutTimer?.cancel(); elapsedSeconds = 0; });
                    }
                  }),
                  const SizedBox(width: 10),
                  actionBtn("기록", Colors.blueGrey, () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryPage(logs: workoutLogs)));
                  }),
                ]),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget statUnit(String label, String val, Color col) => Column(children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)), const SizedBox(height: 10), Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: col))]);
  Widget actionBtn(String label, Color col, VoidCallback fn) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: col, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: fn, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))));
}

// [기록 저장 화면]
class HistoryPage extends StatelessWidget {
  final List<Map<String, String>> logs;
  const HistoryPage({super.key, required this.logs});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록"), backgroundColor: Colors.black),
      body: logs.isEmpty 
        ? const Center(child: Text("저장된 기록이 없습니다."))
        : ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.redAccent),
              title: Text("${logs[index]['date']} 운동 기록"),
              subtitle: Text("시간: ${logs[index]['time']} | 심박수: ${logs[index]['bpm']} BPM"),
            ),
          ),
    );
  }
}

class MiniNeonPainter extends CustomPainter {
  final List<double> points;
  MiniNeonPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.redAccent..strokeWidth = 2.0..style = PaintingStyle.stroke;
    final path = Path();
    final xStep = size.width / (points.length - 1);
    path.moveTo(0, size.height);
    for (int i = 0; i < points.length; i++) {
      path.lineTo(i * xStep, size.height - (points[i] * size.height / 200));
    }
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
