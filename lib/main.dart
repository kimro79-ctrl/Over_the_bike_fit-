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
  int bpm = 98;
  int targetMinutes = 20;
  Duration workoutTime = const Duration(minutes: 0, seconds: 15);
  List<double> heartPoints = List.generate(50, (index) => 0.0);
  Timer? timer;

  @override
  void initState() {
    super.initState();
    // 데이터 시뮬레이션
    timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (mounted) {
        setState(() {
          bpm = 95 + Random().nextInt(10);
          heartPoints.add(Random().nextDouble());
          heartPoints.removeAt(0);
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/background.png"), // 배경 연기 효과 이미지
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black45, BlendMode.darken),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text("Over the Bike Fit", style: TextStyle(fontSize: 22, letterSpacing: 1.2)),
              const SizedBox(height: 30),
              
              // 1. 심박수 & 그래프 영역 (카드 형태)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset("assets/icon/heart.png", width: 40), // 하트 하나만 배치
                        const SizedBox(width: 15),
                        Text("$bpm bpm", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // 심박 그래프
                    SizedBox(
                      height: 100,
                      width: double.infinity,
                      child: CustomPaint(painter: WavePainter(heartPoints)),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // 2. 운동 시간 & 목표 설정 영역
              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        timeColumn("운동시간", "00:15"),
                        verticalDivider(),
                        targetColumn("목표시간"),
                      ],
                    ),
                    const SizedBox(height: 30),
                    // 3. 하단 버튼들
                    Row(
                      children: [
                        actionButton("시작", Colors.red.shade900),
                        const SizedBox(width: 10),
                        actionButton("리셋", Colors.grey.shade800),
                        const SizedBox(width: 10),
                        actionButton("저장", Colors.green.shade900),
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

  Widget timeColumn(String title, String time) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 8),
        Text(time, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.redAccent)),
      ],
    );
  }

  Widget targetColumn(String title) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 5),
        Row(
          children: [
            IconButton(icon: const Icon(Icons.remove, size: 20), onPressed: () {}),
            Text("${targetMinutes}분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () {}),
          ],
        ),
      ],
    );
  }

  Widget verticalDivider() {
    return Container(height: 40, width: 1, color: Colors.white24);
  }

  Widget actionButton(String label, Color color) {
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () {},
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}

// 심박수 파형 그리기
class WavePainter extends CustomPainter {
  final List<double> points;
  WavePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final stepX = size.width / (points.length - 1);

    for (int i = 0; i < points.length; i++) {
      double x = i * stepX;
      double y = (size.height / 2) + (points[i] * 40 * (i % 3 == 0 ? 1 : -1));
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
