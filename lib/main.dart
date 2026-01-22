import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: WidgetsFlutterBinding.ensureInitialized());
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
  int targetMinutes = 20;
  int elapsedSeconds = 0;
  bool isRunning = false;
  double totalCalories = 0;
  Timer? timer;

  void _toggleWorkout() {
    setState(() {
      isRunning = !isRunning;
      if (isRunning) {
        timer = Timer.periodic(const Duration(seconds: 1), (_) {
          setState(() {
            elapsedSeconds++;
            totalCalories = elapsedSeconds * 0.14; // 간단 칼로리 계산 예시
          });
        });
      } else {
        timer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const neon = Color(0xFF00E5FF);
    final timeStr =
        "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}";

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text("OVER THE BIKE FIT",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _info("칼로리", "${totalCalories.toStringAsFixed(1)} kcal", neon),
                        Container(width: 1, height: 20, color: Colors.white24),
                        _info("운동시간", timeStr, Colors.white),
                        Container(width: 1, height: 20, color: Colors.white24),
                        _target(),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isRunning ? Colors.grey : Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                            ),
                            onPressed: _toggleWorkout,
                            child: Text(isRunning ? "정지" : "시작",
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                            ),
                            onPressed: () {},
                            child: const Text("저장", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
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

  Widget _info(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _target() {
    return Expanded(
      child: Column(
        children: [
          const Text("목표설정", style: TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            GestureDetector(
                onTap: () => setState(() {
                      if (targetMinutes > 1) targetMinutes--;
                    }),
                child: const Icon(Icons.remove, size: 16)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text("$targetMinutes분",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            GestureDetector(
                onTap: () => setState(() => targetMinutes++),
                child: const Icon(Icons.add, size: 16)),
          ])
        ],
      ),
    );
  }
}
