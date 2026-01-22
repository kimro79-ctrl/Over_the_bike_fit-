import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BikeFitApp());
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
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
  int _totalHRSum = 0;
  int _hrCount = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  
  bool _isWorkingOut = false;
  bool _isConnecting = false;
  String _watchModel = "기기 없음";
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _hrSubscription;

  List<FlSpot> _hrSpots = [const FlSpot(0, 0)];
  double _timerCounter = 0;

  void _vibrate() => HapticFeedback.lightImpact();

  // [핵심] 실제 블루투스 기기 검색 및 연결 로직
  Future<void> _connectToWatch() async {
    _vibrate();
    
    // 1. 권한 요청 (안드로이드 12+ 대응)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (!statuses[Permission.bluetoothConnect]!.isGranted) {
      _showSnackBar("블루투스 권한이 필요합니다.");
      return;
    }

    setState(() => _isConnecting = true);

    // 2. 블루투스 스캔 시작
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    
    // 3. 기기 찾기 (이름에 Watch가 들어가거나 심박 서비스가 있는 기기 대상)
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.platformName.contains("Watch") || r.device.platformName.contains("Galaxy")) {
          await FlutterBluePlus.stopScan();
          _proceedConnection(r.device);
          break;
        }
      }
    });

    // 5초 후에도 못 찾으면 상태 해제
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _connectedDevice == null) {
        setState(() => _isConnecting = false);
        _showSnackBar("주변에 연결 가능한 워치를 찾지 못했습니다.");
      }
    });
  }

  // 실제 기기 연결 및 심박수 서비스 구독
  Future<void> _proceedConnection(BluetoothDevice device) async {
    try {
      await device.connect();
      List<BluetoothService> services = await device.discoverServices();
      
      for (var service in services) {
        // 심박수 서비스 표준 UUID: 0x180D
        if (service.uuid.toString().toUpperCase().contains("180D")) {
          for (var char in service.characteristics) {
            // 심박수 측정 특성 UUID: 0x2A37
            if (char.uuid.toString().toUpperCase().contains("2A37")) {
              await char.setNotifyValue(true);
              _hrSubscription = char.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  _parseHeartRate(value);
                }
              });
            }
          }
        }
      }

      setState(() {
        _connectedDevice = device;
        _watchModel = device.platformName;
        _isConnecting = false;
      });
      _showSnackBar("${device.platformName} 연결 완료!");
    } catch (e) {
      setState(() => _isConnecting = false);
      _showSnackBar("연결 실패: $e");
    }
  }

  // 워치에서 온 바이트 데이터를 숫자로 변환
  void _parseHeartRate(List<int> data) {
    int hr;
    if (data[0] & 0x01 == 0) {
      hr = data[1]; // 8-bit 심박수
    } else {
      hr = (data[2] << 8) | data[1]; // 16-bit 심박수
    }
    
    if (mounted) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _totalHRSum += hr;
          _hrCount++;
          _avgHeartRate = _totalHRSum ~/ _hrCount;
          _timerCounter += 1.0;
          _hrSpots.add(FlSpot(_timerCounter, hr.toDouble()));
          if (_hrSpots.length > 30) _hrSpots.removeAt(0);
          _calories += (hr * 0.001); // 간이 칼로리 계산식
        }
      });
    }
  }

  void _toggleWorkout() {
    _vibrate();
    if (_connectedDevice == null) {
      _showSnackBar("워치를 먼저 연결해 주세요.");
      return;
    }
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _duration += const Duration(seconds: 1));
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 배경 이미지 (밝기 0.7로 조정)
          Positioned.fill(
            child: Opacity(
              opacity: 0.7,
              child: Image.asset('assets/background.png', fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(color: Colors.black)),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
                
                const SizedBox(height: 15),

                // 2. 워치 연결 버튼
                Center(
                  child: GestureDetector(
                    onTap: _isConnecting || _connectedDevice != null ? null : _connectToWatch,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: _connectedDevice != null ? Colors.cyanAccent : Colors.white38, width: 1.5)
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _isConnecting 
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                            : Icon(Icons.watch, size: 16, color: _connectedDevice != null ? Colors.cyanAccent : Colors.white),
                          const SizedBox(width: 10),
                          Text(_connectedDevice != null ? "연결됨: $_watchModel" : "워치 연결하기", 
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                // 3. 그래프 (배경이 밝으므로 더 두껍게 표현)
                Container(
                  height: 140,
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: LineChart(
                    LineChartData(
                      minY: 40, maxY: 200,
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _hrSpots,
                          isCurved: true, barWidth: 5, color: Colors.redAccent,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: Colors.redAccent.withOpacity(0.2)),
                        )
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // 4. 데이터 배너 (하단 배치 + 투명 그라데이션 + 진한 텍스트)
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.92,
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.15),
                          Colors.black.withOpacity(0.9), // 배경 밝기에 맞춰 배너 가독성 확보
                        ],
                      ),
                      borderRadius: BorderRadius.circular(35),
                      border: Border.all(color: Colors.white24, width: 1.2),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _infoTile(Icons.favorite, "실시간 심박", _heartRate > 0 ? "$_heartRate" : "--", Colors.cyanAccent)),
                            Expanded(child: _infoTile(Icons.trending_up, "평균 심박", _avgHeartRate > 0 ? "$_avgHeartRate" : "--", Colors.redAccent)),
                          ],
                        ),
                        const SizedBox(height: 35),
                        Row(
                          children: [
                            Expanded(child: _infoTile(Icons.local_fire_department, "소모 칼로리", "${_calories.toStringAsFixed(1)}", Colors.orangeAccent)),
                            Expanded(child: _infoTile(Icons.timer, "운동 시간", _formatDuration(_duration), Colors.blueAccent)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 35),

                // 5. 조작 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _circleBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, _isWorkingOut ? "일시정지" : "운동시작", _toggleWorkout),
                      _circleBtn(Icons.save_rounded, "기록저장", () {}),
                      _circleBtn(Icons.insert_chart_rounded, "기록보기", () {}),
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

  Widget _infoTile(IconData icon, String label, String value, Color color) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
        ],
      ),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
    ],
  );

  Widget _circleBtn(IconData icon, String label, VoidCallback onTap) => Column(
    children: [
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 70, height: 70,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24)
          ),
          child: Icon(icon, size: 30, color: Colors.white),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500)),
    ],
  );

  String _formatDuration(Duration d) => 
    "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";

  @override
  void dispose() {
    _hrSubscription?.cancel();
    _connectedDevice?.disconnect();
    _workoutTimer?.cancel();
    super.dispose();
  }
}
