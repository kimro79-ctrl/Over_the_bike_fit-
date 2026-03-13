import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // 그래프용
import 'package:permission_handler/permission_handler.dart'; // 권한용
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart'; // 달력용 (pubspec에 추가 필요)

void main() {
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
  // 상태 변수
  int _heartRate = 0;
  List<FlSpot> _hrSpots = []; // 그래프 데이터
  double _timerStep = 0;
  
  Duration _duration = Duration.zero;
  Timer? _timer;
  bool _isWorkingOut = false;
  
  // 1. 앱 실행 시 권한 요청 (개선사항 5)
  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  // 2. 운동 시작/정지 (개선사항 3)
  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            _duration += const Duration(seconds: 1);
            // 가상 심박수 데이터 생성 (워치 연결 전 테스트용)
            _heartRate = 120 + (t.tick % 20); 
            _hrSpots.add(FlSpot(_timerStep++, _heartRate.toDouble()));
            if (_hrSpots.length > 30) _hrSpots.removeAt(0); // 최근 30초만 표시
          });
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  void _resetWorkout() {
    _timer?.cancel();
    setState(() {
      _isWorkingOut = false;
      _duration = Duration.zero;
      _heartRate = 0;
      _hrSpots.clear();
      _timerStep = 0;
    });
  }

  // 3. 기록 저장 (개선사항 6)
  Future<void> _saveRecord() async {
    if (_duration.inSeconds < 5) return; // 너무 짧으면 저장 안함
    final prefs = await SharedPreferences.getInstance();
    final List<String> records = prefs.getStringList('workout_data') ?? [];
    
    Map<String, dynamic> newRecord = {
      'date': DateTime.now().toIso8601String(),
      'duration': _duration.inSeconds,
      'avgHr': 135, // 가상값
      'kcal': (_duration.inSeconds * 0.12).toStringAsFixed(1),
    };
    
    records.add(jsonEncode(newRecord));
    await prefs.setStringList('workout_data', records);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 타이틀
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Indoor Bike Fit", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const Icon(Icons.watch_rounded, color: Colors.cyanAccent),
                ],
              ),
            ),

            // 4. 심박수 그래프 (개선사항 4)
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(show: false),
                    titlesData: FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _hrSpots,
                        isCurved: true,
                        color: Colors.cyanAccent,
                        barWidth: 3,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)),
                      )
                    ],
                  ),
                ),
              ),
            ),

            // 5. 데이터 바 (개선사항 3: 버튼 위 고정)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(25)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statItem("심박수", "$_heartRate", Colors.greenAccent),
                  _statItem("칼로리", (_duration.inSeconds * 0.1).toStringAsFixed(1), Colors.orangeAccent),
                  _statItem("시간", _formatDuration(_duration), Colors.blueAccent),
                ],
              ),
            ),

            // 6. 하단 버튼부 (개선사항 3: 크기 축소 및 최적화)
            Padding(
              padding: const EdgeInsets.only(bottom: 20, top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _circleBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", _toggleWorkout, Colors.white12),
                  _circleBtn(Icons.refresh, "리셋", _resetWorkout, Colors.white12),
                  _circleBtn(Icons.save_alt, "저장", _saveRecord, Colors.white12),
                  _circleBtn(Icons.calendar_today, "기록", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryPage()));
                  }, Colors.cyanAccent.withOpacity(0.2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) => Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
    ],
  );

  Widget _circleBtn(IconData icon, String label, VoidCallback onTap, Color bg) => Column(
    children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          width: 60, height: 60, // 버튼 크기 축소
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(color: Colors.white10)),
          child: Icon(icon, size: 28, color: Colors.white),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
    ],
  );

  String _formatDuration(Duration d) => "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

// 7. 기록 페이지 (개선사항 6: 실제 데이터 연동)
class HistoryPage extends StatelessWidget {
  const HistoryPage({Key? key}) : super(key: key);

  Future<List<dynamic>> _getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> data = prefs.getStringList('workout_data') ?? [];
    return data.map((e) => jsonDecode(e)).toList().reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("운동 히스토리"), backgroundColor: Colors.black),
      backgroundColor: Colors.black,
      body: FutureBuilder<List<dynamic>>(
        future: _getRecords(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("기록이 없습니다."));
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final item = snapshot.data![index];
              return ListTile(
                leading: const Icon(Icons.directions_bike, color: Colors.cyanAccent),
                title: Text("${item['kcal']} kcal 소모"),
                subtitle: Text("${item['date'].split('T')[0]} | ${item['duration']}초 운동"),
              );
            },
          );
        },
      ),
    );
  }
}
