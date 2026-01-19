import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:math';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
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
  String watchStatus = "탭하여 워치 연결";
  List<double> heartPoints = List.generate(45, (index) => 10.0);
  List<String> workoutHistory = [];

  BluetoothDevice? connectedDevice;
  StreamSubscription? hrSubscription;
  StreamSubscription? scanSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () => FlutterNativeSplash.remove());
    FlutterBluePlus.setLogLevel(LogLevel.verbose); // 디버깅용
  }

  Future<void> _connectWatch() async {
    setState(() => watchStatus = "블루투스 확인 중...");

    // 어댑터 상태 대기
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      setState(() => watchStatus = "블루투스 꺼짐");
      return;
    }

    setState(() => watchStatus = "주변 워치 검색 중...");

    // 기존 스캔 정리
    scanSubscription?.cancel();

    // Heart Rate Service 필터링 스캔
    scanSubscription = FlutterBluePlus.onScanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.advertisementData.serviceUuids.any((g) => g == Guid("180d"))) {
          await FlutterBluePlus.stopScan();
          await _establishConnection(r.device);
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid("180d")],
      timeout: const Duration(seconds: 10),
    );

    FlutterBluePlus.cancelWhenScanComplete(scanSubscription!);
  }

  Future<void> _establishConnection(BluetoothDevice device) async {
    try {
      setState(() => watchStatus = "${device.platformName} 연결 시도...");
      await device.connect(timeout: const Duration(seconds: 10));

      setState(() {
        connectedDevice = device;
        watchStatus = "${device.platformName} 연결됨";
      });

      // 연결 끊김 시 정리
      device.cancelWhenDisconnected(device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            watchStatus = "연결 끊김 • 재연결 시도";
            bpm = 0;
          });
          hrSubscription?.cancel();
          Future.delayed(const Duration(seconds: 3), _connectWatch); // 자동 재시도
        }
      }));

      final services = await device.discoverServices();
      final hrService = services.firstWhere(
        (s) => s.uuid == Guid("180d"),
        orElse: () => throw "HR 서비스 없음",
      );

      final hrChar = hrService.characteristics.firstWhere(
        (c) => c.uuid == Guid("2a37"),
        orElse: () => throw "HR 특성 없음",
      );

      await hrChar.setNotifyValue(true);

      hrSubscription = hrChar.onValueReceived.listen((value) {
        if (!mounted) return;
        final parsedBpm = _parseHeartRate(value);
        if (parsedBpm != null) {
          setState(() {
            bpm = parsedBpm;
            heartPoints.add(parsedBpm.toDouble() / 5);
            if (heartPoints.length > 45) heartPoints.removeAt(0);
          });
        }
      });
    } catch (e) {
      setState(() => watchStatus = "연결 실패: $e • 재시도");
      await device.disconnect();
    }
  }

  int? _parseHeartRate(List<int> value) {
    if (value.isEmpty) return null;
    final flags = value[0];
    final is16bit = (flags & 0x01) != 0;

    if (is16bit) {
      if (value.length < 3) return null;
      return value[1] | (value[2] << 8);
    } else {
      if (value.length < 2) return null;
      return value[1];
    }
  }

  void _toggleWorkout() {
    setState(() {
      isRunning = !isRunning;
      if (isRunning) {
        workoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            elapsedSeconds++;
            if (elapsedSeconds >= targetMinutes * 60) {
              timer.cancel();
              isRunning = false;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("목표 $targetMinutes분 달성! 운동 종료")),
              );
            }
          });
        });
      } else {
        workoutTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    hrSubscription?.cancel();
    workoutTimer?.cancel();
    connectedDevice?.disconnect();
    super.dispose();
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
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(colors: [Colors.white, Colors.redAccent]).createShader(bounds),
                child: const Text(
                  "OVER THE BIKE FIT",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 6, fontStyle: FontStyle.italic),
                ),
              ),
              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.only(top: 15),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    border: Border.all(color: connectedDevice != null ? Colors.greenAccent : Colors.redAccent.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.watch, size: 14, color: connectedDevice != null ? Colors.greenAccent : Colors.grey),
                      const SizedBox(width: 8),
                      Text(watchStatus, style: TextStyle(fontSize: 11, color: connectedDevice != null ? Colors.greenAccent : Colors.white)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (bpm > 0) ...[
                Text("$bpm", style: const TextStyle(fontSize: 90, fontWeight: FontWeight.bold)),
                const Text("BPM", style: TextStyle(color: Colors.redAccent, letterSpacing: 5)),
              ] else ...[
                const Icon(Icons.pedal_bike, size: 80, color: Colors.white24),
                const SizedBox(height: 10),
                const Text("READY TO RIDE", style: TextStyle(color: Colors.grey, letterSpacing: 3)),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    statUnit("운동시간", "\( {(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}: \){(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                    Column(
                      children: [
                        const Text("목표시간", style: TextStyle(color: Colors.grey, fontSize: 10)),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }),
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.white54, size: 20),
                            ),
                            Text("$targetMinutes분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                            IconButton(
                              onPressed: () => setState(() { targetMinutes++; }),
                              icon: const Icon(Icons.add_circle_outline, color: Colors.white54, size: 20),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 50),
                child: Row(
                  children: [
                    actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent, _toggleWorkout),
                    const SizedBox(width: 10),
                    actionBtn("저장", Colors.green.withOpacity(0.7), () {
                      if (elapsedSeconds > 0) {
                        workoutHistory.add("\( {DateTime.now().hour.toString().padLeft(2, '0')}: \){DateTime.now().minute.toString().padLeft(2, '0')} - ${elapsedSeconds ~/ 60}분");
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록 완료")));
                      }
                    }),
                    const SizedBox(width: 10),
                    actionBtn("기록", Colors.blueGrey, () {
                      // 나중에 BottomSheet나 새 화면으로 workoutHistory 보여주기
                    }),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget statUnit(String label, String val, Color col) => Column(
        children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)), const SizedBox(height: 10), Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: col))],
      );

  Widget actionBtn(String label, Color col, VoidCallback fn) => Expanded(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: col,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: fn,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
}
