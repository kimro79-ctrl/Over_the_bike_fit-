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
  int bpm = 104;
  int targetMinutes = 21;
  int elapsedSeconds = 0;
  bool isRunning = false;
  List<double> heartPoints = List.generate(45, (index) => 25.0);
  List<String> workoutHistory = []; 
  Timer? dataTimer;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    dataTimer = Timer.periodic(const Duration(milliseconds: 150), (t) {
      if (mounted) {
        setState(() {
          bpm = 102 + Random().nextInt(8);
          heartPoints.add(Random().nextDouble() * 45 + 5);
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
              const Text("Over the Bike Fit", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w200, letterSpacing: 3)),
              
              // [고급화] 배경과 블렌딩되는 그라데이션 그래프 배너
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.red.withOpacity(0.05), // 배경과 자연스럽게 녹아듦
                      Colors.black.withOpacity(0.9),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.favorite, color: Colors.redAccent, size: 22),
                      const SizedBox(width: 12),
                      Text("$bpm bpm", style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 20),
                    // [고급화] 네온 효과가 들어간 커스텀 곡선 그래프
                    SizedBox(
                      height: 80, 
                      width: double.infinity, 
                      child: CustomPaint(painter: PremiumNeonPainter(heartPoints))
                    ),
                  ],
                ),
              ),

              const Spacer(),
              
              // 하단 조작부
              Container(
                padding: const EdgeInsets.fromLTRB(30, 40, 30, 50),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85), 
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(50))
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      statUnit("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                      Container(width: 1, height: 30, color: Colors.white10),
                      targetUnit(),
                    ]),
                    const SizedBox(height: 35),
                    Row(children: [
                      actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent, toggleWorkout),
                      const SizedBox(width: 15),
                      actionBtn("저장", Colors.green.withOpacity(0.8), () {
                        workoutHistory.add("${DateTime.now().hour}:${DateTime.now().minute} | ${elapsedSeconds}초 완료");
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록 완료!")));
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

  Widget statUnit(String t, String v, Color c) => Column(children: [Text(t, style: const TextStyle(color: Colors.grey, fontSize: 13)), Text(v, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: c))]);
  Widget targetUnit() => Column(children: [
    const Text("목표시간", style: TextStyle(color: Colors.grey, fontSize: 13)),
    Row(children: [
      IconButton(icon: const Icon(Icons.remove, size: 20), onPressed: () => setState(() => targetMinutes--)),
      Text("$targetMinutes분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () => setState(() => targetMinutes++)),
    ])
  ]);
  Widget actionBtn(String t, Color c, VoidCallback f) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: f, child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold))));
}

// [고급화] 하단 채우기 그라데이션이 있는 네온 그래프
class PremiumNeonPainter extends CustomPainter {
  final List<double> points;
  PremiumNeonPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final fillPath = Path();
    final xStep = size.width / (points.length - 1);
    
    path.moveTo(0, size.height - points[0]);
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, size.height - points[0]);

    for (int i = 0; i < points.length - 1; i++) {
      var x1 = i * xStep;
      var y1 = size.height - points[i];
      var x2 = (i + 1) * xStep;
      var y2 = size.height - points[i + 1];
      path.cubicTo(x1 + (xStep / 2), y1, x1 + (xStep / 2), y2, x2, y2);
      fillPath.cubicTo(x1 + (xStep / 2), y1, x1 + (xStep / 2), y2, x2, y2);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // 1. 하단 그라데이션 채우기
    final fillPaint = Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Colors.redAccent.withOpacity(0.3), Colors.transparent],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // 2. 메인 네온 라인 (빛나는 효과)
    final linePaint = Paint()..color = Colors.redAccent..strokeWidth = 3.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
