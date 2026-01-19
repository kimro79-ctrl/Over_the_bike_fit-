import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';

void main() => runApp(const BikeFitApp());

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
  int bpm = 101;
  int targetMinutes = 21;
  int elapsedSeconds = 0;
  bool isRunning = false;
  List<double> heartPoints = List.generate(45, (index) => 25.0);
  Timer? dataTimer;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    dataTimer = Timer.periodic(const Duration(milliseconds: 150), (t) {
      if (mounted) {
        setState(() {
          bpm = 98 + Random().nextInt(10);
          heartPoints.add(Random().nextDouble() * 40 + 5);
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
              const SizedBox(height: 40),
              const Text("Over the Bike Fit", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w200, letterSpacing: 5)),
              
              // 그래프 영역 (배경 일체형)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.red.withOpacity(0.1), Colors.black.withOpacity(0.6)],
                  ),
                ),
                child: Column(
                  children: [
                    Text("$bpm bpm", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 20),
                    SizedBox(height: 80, width: double.infinity, child: CustomPaint(painter: NeonWavePainter(heartPoints))),
                  ],
                ),
              ),

              const Spacer(),
              
              // [요청사항 반영] 버튼부 하단 그라데이션 패널
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(30, 50, 30, 50),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, // 상단은 투명하게 시작하여
                    end: Alignment.bottomCenter, // 하단으로 갈수록 진한 블랙으로
                    colors: [
                      Colors.transparent, 
                      Colors.black.withOpacity(0.8), 
                      Colors.black
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(50)),
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      statUnit("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                      statUnit("목표시간", "$targetMinutes분", Colors.white),
                    ]),
                    const SizedBox(height: 40),
                    Row(children: [
                      actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent, toggleWorkout),
                      const SizedBox(width: 15),
                      actionBtn("저장", Colors.green.withOpacity(0.8), () {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다.")));
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

  Widget statUnit(String label, String val, Color col) => Column(children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)), Text(val, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: col))]);
  Widget actionBtn(String label, Color col, VoidCallback fn) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: col, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: fn, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))));
}

class NeonWavePainter extends CustomPainter {
  final List<double> points;
  NeonWavePainter(this.points);
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
    final paint = Paint()..color = Colors.redAccent..strokeWidth = 3.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
