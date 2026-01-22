import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(const BikeFitApp());

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0;
  int _avgHeartRate = 0;
  List<FlSpot> _hrSpots = [];
  int _timerCount = 0;
  String _watchStatus = "Watch Search";

  // 터치 테스트용
  void _handlePress(String label) {
    print("[$label] 버튼 클릭됨");
    setState(() => _watchStatus = label);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 배경 이미지 (맨 아래)
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover)),

          // 2. 하단 그라데이션 레이어 (배경과 자연스럽게 연결)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                ),
              ),
            ),
          ),

          // 3. 메인 UI (터치 방해 위젯 없음)
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 30),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 15),
                
                // 워치 검색 (단순 컨테이너와 제스처만 사용)
                GestureDetector(
                  onTap: () => _handlePress("Searching..."),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                    ),
                    child: Text(_watchStatus, style: const TextStyle(fontSize: 12, color: Colors.cyanAccent)),
                  ),
                ),

                const SizedBox(height: 15),

                // 그래프 (가늘고 디테일하게)
                SizedBox(
                  height: 60,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(show: false),
                        titlesData: FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _hrSpots.isEmpty ? [const FlSpot(0, 0), const FlSpot(10, 5)] : _hrSpots,
                            isCurved: true,
                            barWidth: 0.8, 
                            color: Colors.cyanAccent.withOpacity(0.8),
                            dotData: FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // 데이터 배너 (투명막/블러 제거, 그라데이션 배경만 적용)
                Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withOpacity(0.08), Colors.transparent],
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataBox("실시간", "$_heartRate", Colors.cyanAccent),
                      _dataBox("평균", "$_avgHeartRate", Colors.redAccent),
                      _dataBox("칼로리", "0.0", Colors.orangeAccent),
                      _dataBox("시간", "00:00", Colors.blueAccent),
                    ],
                  ),
                ),
                const SizedBox(height: 140), 
              ],
            ),
          ),

          // 4. 최상단 버튼 레이어 (모든 레이어 위에 배치)
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _actionButton(Icons.play_arrow, "START", () => _handlePress("START")),
                const SizedBox(width: 15),
                _actionButton(Icons.save, "SAVE", () => _handlePress("SAVE")),
                const SizedBox(width: 15),
                _actionButton(Icons.bar_chart, "LOG", () => _handlePress("LOG")),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataBox(String l, String v, Color c) => Column(
    children: [
      Text(l, style: TextStyle(fontSize: 11, color: Colors.white60)),
      const SizedBox(height: 10),
      Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    ],
  );

  Widget _actionButton(IconData i, String l, VoidCallback t) {
    return GestureDetector(
      onTap: t,
      behavior: HitTestBehavior.opaque, 
      child: Container(
        width: 100, height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          gradient: LinearGradient(
            colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.05)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(i, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(l, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
