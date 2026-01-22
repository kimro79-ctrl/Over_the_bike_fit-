import 'dart:async';
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
  String _watchModel = "연결 대기 중";
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _hrSubscription;

  List<FlSpot> _hrSpots = [const FlSpot(0, 0)];
  double _timerCounter = 0;

  void _vibrate() => HapticFeedback.lightImpact();

  // 실제 블루투스 워치 검색 및 연결
  Future<void> _connectToWatch() async {
    _vibrate();
    
    // 블루투스 권한 체크
    var status = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (status[Permission.bluetoothConnect] != PermissionStatus.granted) {
      _msg("블루투스 권한을 승인해주세요.");
      return;
    }

    setState(() => _isConnecting = true);

    // 스캔 시작
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      
      FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          // 이름에 Watch나 Galaxy가 들어간 기기를 자동 연결 시도
          if (r.device.platformName.contains("Watch") || r.device.platformName.contains("Galaxy")) {
            await FlutterBluePlus.stopScan();
            _attemptConnection(r.device);
            break;
          }
        }
      });
    } catch (e) {
      setState(() => _isConnecting = false);
      _msg("스캔 오류: $e");
    }
  }

  Future<void> _attemptConnection(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      List<BluetoothService> services = await device.discoverServices();
      
      for (var service in services) {
        // 심박수 표준 서비스 UUID
        if (service.uuid.toString().toUpperCase().contains("180D")) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toUpperCase().contains("2A37")) {
              await char.setNotifyValue(true);
              _hrSubscription = char.lastValueStream.listen((value) {
                if (value.isNotEmpty) _processHR(value);
              });
            }
          }
        }
      }

      setState(() {
        _connectedDevice = device;
        _watchModel = "연결됨: ${device.platformName}";
        _isConnecting = false;
      });
    } catch (e) {
      setState(() => _isConnecting = false);
      _msg("연결 실패. 워치의 '심박수 공유'를 확인하세요.");
    }
  }

  void _processHR(List<int> data) {
    int hr = data[0] & 0x01 == 0 ? data[1] : (data[2] << 8) | data[1];
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
          _calories += (hr * 0.0012); 
        }
      });
    }
  }

  void _toggleWorkout() {
    _vibrate();
    if (_connectedDevice == null) {
      _msg("워치를 먼저 연결해주세요.");
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

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 배경 이미지 - 밝게 조절 (Opacity 0.8)
          Positioned.fill(
            child: Opacity(
              opacity: 0.8, 
              child: Image.asset('assets/background.png', fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(color: Colors.red[900])),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2)),
                
                const SizedBox(height: 20),

                // 워치 연결 버튼 (사진 스타일)
                Center(
                  child: InkWell(
                    onTap: _connectedDevice == null ? _connectToWatch : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 1.5)
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.watch, size: 18, color: _connectedDevice != null ? Colors.cyanAccent : Colors.white),
                          const SizedBox(width: 10),
                          Text(_isConnecting ? "검색 중..." : _watchModel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // 데이터 배너 (사진 스타일 - 하단 배치 + 투명도 조절)
                Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(35),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _tile(Icons.favorite, "실시간 심박", "$_heartRate", Colors.cyanAccent)),
                          Expanded(child: _tile(Icons.trending_up, "평균 심박", "$_avgHeartRate", Colors.redAccent)),
                        ],
                      ),
                      const SizedBox(height: 40),
                      Row(
                        children: [
                          Expanded(child: _tile(Icons.local_fire_department, "소모 칼로리", "${_calories.toStringAsFixed(1)}", Colors.orangeAccent)),
                          Expanded(child: _tile(Icons.timer, "운동 시간", _formatDuration(_duration), Colors.blueAccent)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // 하단 원형 버튼 (사진 스타일)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작/정지", _toggleWorkout),
                      _btn(Icons.file_download, "기록 저장", () {}),
                      _btn(Icons.bar_chart, "기록 보기", () {}),
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

  Widget _tile(IconData i, String l, String v, Color c) => Column(
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 14, color: c), const SizedBox(width: 6), Text(l, style: const TextStyle(fontSize: 12, color: Colors.white70))]),
      const SizedBox(height: 10),
      Text(v, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
    ],
  );

  Widget _btn(IconData i, String l, VoidCallback t) => Column(
    children: [
      InkWell(
        onTap: t,
        child: Container(
          width: 75, height: 75,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
          child: Icon(i, size: 30, color: Colors.white),
        ),
      ),
      const SizedBox(height: 10),
      Text(l, style: const TextStyle(fontSize: 12, color: Colors.white70)),
    ],
  );

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";

  @override
  void dispose() {
    _hrSubscription?.cancel();
    _connectedDevice?.disconnect();
    _workoutTimer?.cancel();
    super.dispose();
  }
}
