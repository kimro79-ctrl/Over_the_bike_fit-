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
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
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
  int bpm = 0;
  int targetMinutes = 20;
  int elapsedSeconds = 0;
  bool isRunning = false;
  double totalCalories = 0.0;
  List<FlSpot> heartRateSpots = [];
  Timer? workoutTimer;

  // 하단 아이템 위젯 (칼로리, 시간 등)
  Widget _infoItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // 목표 설정 위젯 (더하기/빼기 포함)
  Widget _targetSelector() {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("목표설정", style: TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(onTap: () => setState(() => targetMinutes--), child: const Icon(Icons.remove, size: 16)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text("$targetMinutes분", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              GestureDetector(onTap: () => setState(() => targetMinutes++), child: const Icon(Icons.add, size: 16)),
            ],
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color neonColor = Color(0xFF00E5FF);
    String timeStr = "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}";

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 15),
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
              
              const Spacer(),

              // 하단 컨트롤 영역
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
                    // [일렬 배치 섹션] 칼로리 | 시간 | 목표
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _infoItem("칼로리", "${totalCalories.toStringAsFixed(1)} kcal", neonColor),
                        Container(width: 1, height: 20, color: Colors.white24), // 구분선
                        _infoItem("운동시간", timeStr, Colors.white),
                        Container(width: 1, height: 20, color: Colors.white24), // 구분선
                        _targetSelector(),
                      ],
                    ),
                    const SizedBox(height: 30),
                    // 버튼 영역
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isRunning ? Colors.grey : Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              setState(() {
                                isRunning = !isRunning;
                                if (isRunning) {
                                  workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                                } else {
                                  workoutTimer?.cancel();
                                }
                              });
                            },
                            child: Text(isRunning ? "정지" : "시작", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {},
                            child: const Text("저장", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
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
}
