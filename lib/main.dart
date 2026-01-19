import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
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
    // 3초간 스플래시 유지 후 부드럽게 전환
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      setState(() => _isReady = true);
    }
    // 자연스러운 전환을 위해 아주 짧은 딜레이 후 스플래시 제거
    Timer(const Duration(milliseconds: 500), () => FlutterNativeSplash.remove());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      // AnimatedOpacity를 사용하여 메인 화면이 부드럽게 나타나게 함
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
  int targetMinutes = 21;
  int elapsedSeconds = 0;
  bool isRunning = false;
  List<double> heartPoints = List.generate(45, (index) => 15.0);
  Timer? dataTimer;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    dataTimer = Timer.periodic(const Duration(milliseconds: 150), (t) {
      if (mounted) {
        setState(() {
          bpm = 98 + Random().nextInt(8);
          heartPoints.add(Random().nextDouble() * 25 + 5);
          heartPoints.removeAt(0);
        });
      }
    });
  }

  void toggleWorkout() {
    setState(() {
      isRunning = !isRunning;
      if (isRunning) {
        workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
      } else {
        workoutTimer?.cancel();
      }
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
              const SizedBox(height: 30),
              const Text("Over the Bike Fit", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w200, letterSpacing: 4)),
              
              // [수정] 크기를 줄인 상단 네온 배너
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.red.withOpacity(0.08), Colors.black.withOpacity(0.5)],
                  ),
                ),
                child: Column(
                  children: [
                    // [수정] BPM 텍스트 크기 축소 (36 -> 28)
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.favorite, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 10),
                      Text("$bpm bpm", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 10),
                    // [수정] 그래프 높이 축소 (80 -> 50)
                    SizedBox(
                      height: 50, 
                      width: double.infinity, 
                      child: CustomPaint(painter: SlimNeonPainter(heartPoints))
                    ),
                  ],
                ),
              ),

              const Spacer(),
              
              // 하단 컨트롤 패널 (그라데이션 유지)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(30, 40, 30, 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8), Colors.black],
                  ),
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      statUnit("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                      statUnit("목표시간", "$targetMinutes분", Colors.white),
                    ]),
                    const SizedBox(height: 30),
                    Row(children: [
                      actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent, toggleWorkout),
                      const SizedBox(width: 15),
                      actionBtn("저장", Colors.green.withOpacity(0.7), () {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록 완료")));
                      }),
                    ]),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget statUnit(String label, String val, Color col) => Column(children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)), Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: col))]);
  Widget actionBtn(String label, Color col, VoidCallback fn) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: col, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: fn, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))));
}

// [수정] 더 얇고 세밀해진 네온 곡선 Painter
class SlimNeonPainter extends CustomPainter {
  final List<double> points;
  SlimNeonPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final xStep = size.width / (points.length - 1);
    path.moveTo(0, size.height - points[0]);
    for (int i = 0; i < points.length - 1; i++) {
      var x1 = i * xStep;
      var y1 = size.height - points[i];
      var x2 = (i + 1) * xStep;
      var y2 = size.height - points[i + 1];
      path.cubicTo(x1 + (xStep / 2), y1, x1 + (xStep / 2), y2, x2, y2);
    }
    // 선 두께를 3.5 -> 2.0으로 줄임
    final paint = Paint()..color = Colors.redAccent..strokeWidth = 2.0..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
