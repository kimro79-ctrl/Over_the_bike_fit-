import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
  bool _isWorkingOut = false;
  String _watchStatus = "워치 검색 중...";

  @override
  void initState() {
    super.initState();
    _startWatchScan(); // 앱 실행 시 자동으로 워치 검색 (시작 버튼과 분리)
  }

  // 워치 검색 로직 (독립 실행)
  void _startWatchScan() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName.contains("Watch")) {
          setState(() => _watchStatus = "연결됨: ${r.device.platformName}");
          // 여기에 실제 연결(connect) 및 리스닝 로직 추가
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final boxColor = Colors.black.withOpacity(0.5); // 배너와 버튼 동일 색상

    return Scaffold(
      body: Stack(
        children: [
          // 배경 및 하단 그라데이션
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover)),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                
                // 워치 상태창 (작고 상단에 고정)
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                  ),
                  child: Text(_watchStatus, style: const TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                ),

                const Spacer(),

                // 데이터 배너 (하단부, 더 흐리게)
                Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: boxColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _data("심박수", "$_heartRate", Colors.cyanAccent),
                      _data("칼로리", "0.0", Colors.orangeAccent),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // 조작 버튼 (사각형, 작게, 배너와 동일 색상)
                Padding(
                  padding: const EdgeInsets.bottom(40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _btn(Icons.play_arrow, "시작", boxColor, () => setState(() => _isWorkingOut = true)),
                      const SizedBox(width: 20),
                      _btn(Icons.save, "저장", boxColor, () {}),
                      const SizedBox(width: 20),
                      _btn(Icons.bar_chart, "기록", boxColor, () {}),
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _data(String l, String v, Color c) => Column(
    children: [
      Text(l, style: TextStyle(fontSize: 12, color: c)),
      Text(v, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
    ],
  );

  Widget _btn(IconData i, String l, Color bg, VoidCallback t) => Column(
    children: [
      InkWell(
        onTap: t,
        child: Container(
          width: 55, height: 55,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
          child: Icon(i, size: 24),
        ),
      ),
      const SizedBox(height: 5),
      Text(l, style: const TextStyle(fontSize: 10, color: Colors.white50)),
    ],
  );
}
