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
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _isReady = true);
    Timer(const Duration(milliseconds: 500), () => FlutterNativeSplash.remove());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
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
  int targetMinutes = 20;
  int elapsedSeconds = 0;
  bool isRunning = false;
  List<double> heartPoints = List.generate(45, (index) => 10.0);
  List<String> workoutHistory = [];
  Timer? dataTimer;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    dataTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (mounted) {
        setState(() {
          bpm = 95 + Random().nextInt(10);
          heartPoints.add(Random().nextDouble() * 15 + 5);
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

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.95),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(25),
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          children: [
            const Text("운동 기록", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            const Divider(color: Colors.white10, height: 30),
            Expanded(
              child: workoutHistory.isEmpty
                  ? const Center(child: Text("저장된 기록이 없습니다."))
                  : ListView.builder(
                      itemCount: workoutHistory.length,
                      itemBuilder: (context, index) => ListTile(
                        leading: const Icon(Icons.history, color: Colors.grey, size: 20),
                        title: Text(workoutHistory[index], style: const TextStyle(fontSize: 14)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
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
              const Text("Over the Bike Fit", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w200, letterSpacing: 5)),
              
              // [크기 유지] 상단 미니 BPM 영역
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 60, vertical: 25),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.red.withOpacity(0.05), Colors.black.withOpacity(0.4)],
                  ),
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.favorite, color: Colors.redAccent, size: 14),
                      const SizedBox(width: 8),
                      Text("$bpm bpm", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 8),
                    SizedBox(height: 30, width: double.infinity, child: CustomPaint(painter: MiniNeonPainter(heartPoints))),
                  ],
                ),
              ),

              const Spacer(),
              
              // 하단 패널
              Container(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 50),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.9), Colors.black],
                  ),
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      statUnit("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                      statUnit("목표시간", "$targetMinutes분", Colors.white),
                    ]),
                    const SizedBox(height: 35),
                    
                    // [수정] 버튼 밸런스: 3개의 버튼을 동일한 크기로 나란히 배치
                    Row(
                      children: [
                        actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent, toggleWorkout),
                        const SizedBox(width: 10),
                        actionBtn("저장", Colors.green.withOpacity(0.7), () {
                          setState(() {
                            workoutHistory.add("${DateTime.now().hour}:${DateTime.now().minute} - ${elapsedSeconds ~/ 60}분 운동완료");
                          });
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록 저장됨")));
                        }),
                        const SizedBox(width: 10),
                        actionBtn("기록", Colors.blueGrey, _showHistory),
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

  Widget statUnit(String label, String val, Color col) => Column(children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)), Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: col))]);

  // 버튼 크기 밸런스를 위한 위젯
  Widget actionBtn(String label, Color col, VoidCallback fn) => Expanded(
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: col, 
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
      ),
      onPressed: fn, 
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))
    )
  );
}

class MiniNeonPainter extends CustomPainter {
  final List<double> points;
  MiniNeonPainter(this.points);
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
    final paint = Paint()..color = Colors.redAccent..strokeWidth = 1.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
