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
  // 상태 변수들
  int bpm = 98;
  int targetMinutes = 20;
  int elapsedSeconds = 15;
  bool isRunning = false;
  List<double> heartPoints = List.generate(40, (index) => 0.5);
  
  Timer? dataTimer;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    startDataSim(); // 심박수 시뮬레이션 시작
  }

  // 심박수 및 그래프 데이터 업데이트
  void startDataSim() {
    dataTimer = Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (mounted) {
        setState(() {
          bpm = 95 + Random().nextInt(8);
          heartPoints.add(Random().nextDouble());
          heartPoints.removeAt(0);
        });
      }
    });
  }

  // 운동 시간 타이머 제어
  void toggleWorkout() {
    setState(() {
      isRunning = !isRunning;
      if (isRunning) {
        workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => elapsedSeconds++);
        });
      } else {
        workoutTimer?.cancel();
      }
    });
  }

  void resetWorkout() {
    setState(() {
      isRunning = false;
      workoutTimer?.cancel();
      elapsedSeconds = 0;
    });
  }

  String formatTime(int seconds) {
    int mins = seconds ~/ 60;
    int secs = seconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    dataTimer?.cancel();
    workoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/background.png"),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Text("Over the Bike Fit", style: TextStyle(fontSize: 20, letterSpacing: 1.5, fontWeight: FontWeight.w300)),
              
              // 1. 슬림해진 심박수 & 그래프 박스
              Container(
                margin: const EdgeInsets.fromLTRB(25, 20, 25, 10),
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset("assets/icon/heart.png", width: 25),
                        const SizedBox(width: 12),
                        Text("$bpm bpm", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 크기를 줄인 그래프
                    SizedBox(
                      height: 60, 
                      width: double.infinity,
                      child: CustomPaint(painter: WavePainter(heartPoints)),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // 2. 하단 컨트롤 패널
              Container(
                padding: const EdgeInsets.fromLTRB(30, 30, 30, 40),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 운동 시간 (실제 작동)
                        Expanded(
                          child: Column(
                            children: [
                              const Text("운동시간", style: TextStyle(color: Colors.grey, fontSize: 13)),
                              const SizedBox(height: 8),
                              Text(formatTime(elapsedSeconds), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 40, color: Colors.white12),
                        // 목표 시간 (조절 가능)
                        Expanded(
                          child: Column(
                            children: [
                              const Text("목표시간", style: TextStyle(color: Colors.grey, fontSize: 13)),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(icon: const Icon(Icons.remove, size: 18), onPressed: () => setState(() => targetMinutes--)),
                                  Text("${targetMinutes}분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                                  IconButton(icon: const Icon(Icons.add, size: 18), onPressed: () => setState(() => targetMinutes++)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    // 3. 작동 버튼 세트
                    Row(
                      children: [
                        actionButton(isRunning ? "정지" : "시작", isRunning ? Colors.orange.shade900 : Colors.red.shade900, toggleWorkout),
                        const SizedBox(width: 12),
                        actionButton("리셋", Colors.grey.shade800, resetWorkout),
                        const SizedBox(width: 12),
                        actionButton("저장", Colors.green.shade900, () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다!")));
                        }),
                      ],
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

  Widget actionButton(String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        ),
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  final List<double> points;
  WavePainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.redAccent..strokeWidth = 2.0..style = PaintingStyle.stroke;
    final path = Path();
    final stepX = size.width / (points.length - 1);
    for (int i = 0; i < points.length; i++) {
      double x = i * stepX;
      double y = (size.height / 2) + (points[i] * 25 * (i % 2 == 0 ? 1 : -1));
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
