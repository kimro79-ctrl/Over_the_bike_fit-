class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final Function onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // 최근 7일 통계 계산
  Map<String, dynamic> _getWeeklySummary() {
    double totalCalories = 0;
    int totalMinutes = 0;
    DateTime now = DateTime.now();
    DateTime sevenDaysAgo = now.subtract(const Duration(days: 7));

    for (var record in widget.records) {
      DateTime recordDate = DateTime.parse(record.id); 
      if (recordDate.isAfter(sevenDaysAgo)) {
        totalCalories += record.calories;
        totalMinutes += record.duration.inMinutes;
      }
    }
    return {'calories': totalCalories, 'minutes': totalMinutes};
  }

  @override
  Widget build(BuildContext context) {
    final weeklyStats = _getWeeklySummary();
    final filtered = widget.records.where((r) => _selectedDay == null || r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212), // 다크 모드 배경
      appBar: AppBar(
        title: const Text("운동 히스토리", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // 💡 차분한 그라데이션 주간 요약 대시보드
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF232526), Color(0xFF414345)], // 차분한 다크 그레이 그라데이션
              ),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryItem("최근 7일 시간", "${weeklyStats['minutes']}분", Icons.timer_outlined, Colors.blueAccent),
                Container(width: 1, height: 40, color: Colors.white12),
                _summaryItem("최근 7일 칼로리", "${weeklyStats['calories'].toStringAsFixed(0)} kcal", Icons.local_fire_department_rounded, Colors.orangeAccent),
              ],
            ),
          ),
          
          TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1), lastDay: DateTime.utc(2030, 12, 31), focusedDay: _focusedDay, locale: 'ko_KR',
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            eventLoader: (day) {
              String formatted = DateFormat('yyyy-MM-dd').format(day);
              return widget.records.where((r) => r.date == formatted).toList();
            },
            calendarStyle: const CalendarStyle(
              defaultTextStyle: TextStyle(color: Colors.white70),
              weekendTextStyle: TextStyle(color: Colors.redAccent),
              markerDecoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
              selectedDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
              todayDecoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
            ),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(color: Colors.white10, thickness: 1),
          ),
          Expanded(
            child: filtered.isEmpty 
              ? const Center(child: Text("기록이 없습니다.", style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 10),
                  itemCount: filtered.length,
                  itemBuilder: (c, i) => _buildRecordCard(filtered[i]),
                ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon, Color iconColor) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildRecordCard(WorkoutRecord r) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), 
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: InkWell(
        onLongPress: () => _showDeleteDialog(r),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.directions_bike, color: Colors.blueAccent, size: 22),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.date, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text("${r.duration.inMinutes}분 운동 / 평균 ${r.avgHR}bpm", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
              ),
              Text("${r.calories.toStringAsFixed(1)}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 18)),
              const Text(" kcal", style: TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(WorkoutRecord r) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2C),
      title: const Text("기록 삭제", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: const Text("이 기록을 삭제하시겠습니까?", style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소", style: TextStyle(color: Colors.white38))),
        TextButton(onPressed: () {
          setState(() { widget.records.removeWhere((rec) => rec.id == r.id); });
          widget.onSync();
          Navigator.pop(context);
        }, child: const Text("삭제", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
      ],
    ));
  }
}
