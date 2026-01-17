import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(const OverTheBikeFit());

class OverTheBikeFit extends StatelessWidget {
  const OverTheBikeFit({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const CyclingHomeScreen(),
    );
  }
}

class CyclingHomeScreen extends StatefulWidget {
  const CyclingHomeScreen({super.key});
  @override
  State<CyclingHomeScreen> createState() => _CyclingHomeScreenState();
}

class _CyclingHomeScreenState extends State<CyclingHomeScreen> {
  bool isRunning = false;
  int seconds = 0;
  double heartRate = 98;
  List<FlSpot> hrPoints = List.generate(10, (i) => FlSpot(i.toDouble(), 90.0 + Random().nextInt(10)));
  Timer? timer;

  void toggleTimer() {
    setState(() {
      if (isRunning) {
        timer?.cancel();
        isRunning = false;
      } else {
        isRunning = true;
        timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            seconds++;
            heartRate = 95.0 + Random().nextInt(15);
            hrPoints.add(FlSpot(hrPoints.length.toDouble(), heartRate));
            if (hrPoints.length > 20) hrPoints.removeAt(0);
          });
        });
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
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('CYCLE FIT', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.redAccent)),
              ),
              _buildChartCard(),
              const Spacer(),
              _buildInfoRow(),
              _buildButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      height: 250,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("실시간 심박수", style: TextStyle(color: Colors.white70)),
              Text("${heartRate.toInt()} bpm", style: const TextStyle(fontSize: 24, color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: hrPoints,
                    isCurved: true,
                    color: Colors.redAccent,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: Colors.redAccent.withOpacity(0.2)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _infoBox('운동시간', _formatTime(seconds), Colors.redAccent),
          const SizedBox(width: 10),
          _infoBox('목표', '20분', Colors.white),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: toggleTimer,
              style: ElevatedButton.styleFrom(backgroundColor: isRunning ? Colors.red[900] : Colors.red, padding: const EdgeInsets.all(15)),
              child: Text(isRunning ? '정지' : '시작', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => setState(() { seconds = 0; isRunning = false; timer?.cancel(); }),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800], padding: const EdgeInsets.all(15)),
              child: const Text('리셋'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(String t, String v, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15)),
      child: Column(children: [Text(t, style: const TextStyle(color: Colors.white54)), Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c))]),
    ),
  );

  String _formatTime(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}
