import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // 블루투스 추가
import 'dart:async';
import 'dart:math';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
}

class BikeFitApp extends StatefulWidget {
  const BikeFitApp({super.key});
  @override
  State<BikeFitApp> createState() => _BikeFitAppState();
}

class _BikeFitAppState extends State<BikeFitApp> {
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _loadApp();
  }

  void _loadApp() async {
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _isReady = true);
    Timer(const Duration(milliseconds: 500), () => FlutterNativeSplash.remove());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'Orbitron', letterSpacing: 8), // 세련된 폰트 느낌 유도
        ),
      ),
      home: AnimatedOpacity(
        opacity: _isReady ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 800),
        child: const WorkoutScreen(),
      ),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});
  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int bpm = 101;
  int targetMinutes = 20;
  int elapsedSeconds = 0;
  bool isRunning = false;
  List<double> heartPoints = List.generate(45, (index) => 10.0);
  List<String> workoutHistory = [];
  
  // 스마트워치 연동 상태
  String watchStatus = "워치 미연동";

  @override
  void initState() {
    super.initState();
    _startSimulatedData();
  }

  void _startSimulatedData() {
    Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (mounted) {
        setState(() {
          bpm = 95 + Random().nextInt(10);
          heartPoints.add(Random().nextDouble() * 15 + 5);
          heartPoints.removeAt(0);
        });
      }
    });
  }

  // 스마트워치 스캔 함수 (뼈대)
  void _connectWatch() async {
    setState(() => watchStatus = "스캔 중...");
    // 실제 구현 시 권한 체크 및 기기 선택 로직이 필요합니다.
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    
    // 시연용 상태 변경
    Timer(const Duration(seconds: 2), () {
      setState(() => watchStatus = "스마트워치 연결됨");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              // [디자인 개선] 텍스트 스타일링
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.white, Colors.redAccent],
                ).createShader(bounds),
                child: const Text(
                  "OVER THE BIKE FIT",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              
              // 워치 상태 표시
              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(watchStatus, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ),
              ),

              const Spacer(),
              
              // 하단 컨트롤 패널
              Container(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 50),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.9), Colors.black],
                  ),
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      statUnit("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                      statUnit("목표시간", "$targetMinutes분", Colors.white),
                    ]),
                    const SizedBox(height: 35),
                    Row(
                      children: [
                        actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent, () {
                          setState(() {
                            isRunning = !isRunning;
                            if (isRunning) {
                              Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                            }
                          });
                        }),
                        const SizedBox(width: 10),
                        actionBtn("저장", Colors.green.withOpacity(0.7), () {}),
                        const SizedBox(width: 10),
                        actionBtn("기록", Colors.blueGrey, () {}),
                      ],
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget statUnit(String label, String val, Color col) => Column(children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)), Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: col))]);
  Widget actionBtn(String label, Color col, VoidCallback fn) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: col, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: fn, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))));
}

// (그래프 Painter 클래스는 이전과 동일하므로 생략 가능하나 전체 코드 작동을 위해 포함)
class MiniNeonPainter extends CustomPainter {
  final List<double> points;
  MiniNeonPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final xStep = size.width / (points.length - 1);
    path.moveTo(0, size.height - points[0]);
    for (int i = 0; i < points.length - 1; i++) {
      var x1 = i * xStep; var y1 = size.height - points[i];
      var x2 = (i + 1) * xStep; var y2 = size.height - points[i + 1];
      path.cubicTo(x1 + (xStep / 2), y1, x1 + (xStep / 2), y2, x2, y2);
    }
    canvas.drawPath(path, Paint()..color = Colors.redAccent..strokeWidth = 1.5..style = PaintingStyle.stroke);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
