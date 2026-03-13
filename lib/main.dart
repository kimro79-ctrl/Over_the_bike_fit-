import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

void main() => runApp(const BikeFitApp());

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
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
  double _calories = 0.0;
  List<FlSpot> _hrSpots = [];
  Duration _duration = Duration.zero;
  Timer? _timer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;

  // 칼로리 계산 로직 (심박수 85 이상일 때만 초당 계산)
  void _calculateCalories() {
    if (_isWorkingOut && _heartRate >= 85) {
      // 대략적인 공식: (심박수 * 0.001) 정도를 초당 소모량으로 가정
      setState(() {
        _calories += (_heartRate * 0.0005); 
      });
    }
  }

  // 실제 데이터 수신 함수 (워치 연동 시 이 함수를 호출하게 됨)
  void onHeartRateReceived(int rate) {
    setState(() {
      _heartRate = rate;
      if (_isWorkingOut) {
        _hrSpots.add(FlSpot(_duration.inSeconds.toDouble(), _heartRate.toDouble()));
        if (_hrSpots.length > 50) _hrSpots.removeAt(0);
        _calculateCalories();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/background.png'), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              const Spacer(),
              Image.asset('assets/icon/bike_ui_dark.png', width: 220, errorBuilder: (c,e,s) => const Icon(Icons.directions_bike, size: 100)),
              const SizedBox(height: 20),
              if (_isWatchConnected) _buildGraph() else const SizedBox(height: 120, child: Center(child: Text("워치를 연결하면 그래프가 표시됩니다."))),
              _buildDataPanel(),
              _buildBottomButtons(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Indoor bike fit", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          ActionChip(
            label: Text(_isWatchConnected ? "연결됨" : "워치 연결"),
            onPressed: () => setState(() => _isWatchConnected = !_isWatchConnected),
            backgroundColor: _isWatchConnected ? Colors.cyanAccent.withOpacity(0.3) : Colors.white10,
          ),
        ],
      ),
    );
  }

  Widget _buildGraph() {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 30),
      child: LineChart(LineChartData(
        minY: 60, maxY: 200,
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [LineChartBarData(spots: _hrSpots, isCurved: true, color: Colors.cyanAccent, dotData: FlDotData(show: false))],
      )),
    );
  }

  Widget _buildDataPanel() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statCol("심박수", "$_heartRate", Colors.greenAccent),
          _statCol("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
          _statCol("시간", _formatDuration(_duration), Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _iconBtn(Icons.play_arrow, "시작", () {
          setState(() {
            _isWorkingOut = !_isWorkingOut;
            if (_isWorkingOut) {
              _timer = Timer.periodic(const Duration(seconds: 1), (t) {
                setState(() => _duration += const Duration(seconds: 1));
                _calculateCalories(); // 1초마다 칼로리 체크
              });
            } else { _timer?.cancel(); }
          });
        }),
        _iconBtn(Icons.refresh, "리셋", () => setState(() { _duration = Duration.zero; _calories = 0.0; _hrSpots.clear(); })),
        _iconBtn(Icons.save, "저장", () {}),
        _iconBtn(Icons.calendar_month, "기록", () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen()));
        }),
      ],
    );
  }

  Widget _statCol(String l, String v, Color c) => Column(children: [
    Text(l, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    Text(v, style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.bold))
  ]);

  Widget _iconBtn(IconData i, String l, VoidCallback t) => Column(children: [
    GestureDetector(onTap: t, child: Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: Icon(i, color: Colors.white))),
    const SizedBox(height: 5),
    Text(l, style: const TextStyle(fontSize: 11, color: Colors.white70))
  ]);

  String _formatDuration(Duration d) => "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

// --- 기록 페이지 (이미지 1000014247.jpg 복구) ---
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(title: const Text("기록 리포트", style: TextStyle(color: Colors.black)), backgroundColor: Colors.white, elevation: 0, leading: const BackButton(color: Colors.black)),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(15),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF5D7F8F), borderRadius: BorderRadius.circular(15)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text("나의 현재 체중", style: TextStyle(color: Colors.white70)), Text("69.7kg", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))]),
            ),
            TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1), lastDay: DateTime.utc(2030, 12, 31), focusedDay: DateTime.now(),
              calendarStyle: const CalendarStyle(todayDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
            ),
            const SizedBox(height: 20),
            _historyTile("6 kcal 소모", "2분 / 88 bpm"),
            _historyTile("90 kcal 소모", "10분 / 117 bpm"),
          ],
        ),
      ),
    );
  }

  Widget _historyTile(String t, String s) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
    child: ListTile(
      leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.directions_bike, color: Colors.white)),
      title: Text(t, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      subtitle: Text(s, style: const TextStyle(color: Colors.grey)),
    ),
  );
}
