import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui';

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
  String _watchStatus = "워치 검색을 시작하세요";
  bool _isWorkingOut = false;

  // [중요] 워치 검색 버튼 클릭 시 실행
  Future<void> _handleWatchSearch() async {
    // 1. 필수 권한 요청 (블루투스, 위치)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // 2. 권한 허용 확인 후 기기 탐색
    if (statuses.values.every((status) => status.isGranted)) {
      _startScanning();
    } else {
      setState(() => _watchStatus = "권한 허용이 필요합니다");
    }
  }

  void _startScanning() async {
    setState(() => _watchStatus = "주변 워치 찾는 중...");
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        // 샤오미(Amazfit), 갤럭시, 일반적인 Watch 이름 모두 검색
        if (name.contains("watch") || name.contains("amazfit") || name.contains("gtr") || name.contains("gts")) {
          setState(() => _watchStatus = "발견됨: ${r.device.platformName}");
          // 여기서 r.device.connect() 로직으로 연결 가능
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover)),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.3))),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                // 워치 검색 버튼 (클릭 시 권한 팝업 발생)
                GestureDetector(
                  onTap: _handleWatchSearch,
                  behavior: HitTestBehavior.opaque, // 터치 민감도 최대로
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search, size: 14, color: Colors.cyanAccent),
                        const SizedBox(width: 8),
                        Text(_watchStatus, style: const TextStyle(fontSize: 11, color: Colors.white)),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // 데이터 배너 (유리 효과)
                _glassPanel(
                  width: MediaQuery.of(context).size.width * 0.9,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _infoText("실시간", "$_heartRate", Colors.cyanAccent),
                      _infoText("평균", "$_avgHeartRate", Colors.redAccent),
                      _infoText("칼로리", "0.0", Colors.orangeAccent),
                      _infoText("시간", "00:00", Colors.blueAccent),
                    ],
                  ),
                ),

                const SizedBox(height: 35),

                // 하단 사각형 버튼 (유리 효과)
                Padding(
                  padding: const EdgeInsets.only(bottom: 50),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _glassActionBtn(Icons.play_arrow, "시작", () => setState(() => _isWorkingOut = !_isWorkingOut)),
                      const SizedBox(width: 20),
                      _glassActionBtn(Icons.save, "저장", () {}),
                      const SizedBox(width: 20),
                      _glassActionBtn(Icons.bar_chart, "기록", () {}),
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

  Widget _infoText(String l, String v, Color c) => Column(
    children: [
      Text(l, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
    ],
  );

  Widget _glassPanel({required double width, required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _glassActionBtn(IconData i, String l, VoidCallback t) => Column(
    children: [
      GestureDetector(
        onTap: t,
        behavior: HitTestBehavior.opaque,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(i, size: 26, color: Colors.white),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(l, style: const TextStyle(fontSize: 10, color: Colors.white38)),
    ],
  );
}
