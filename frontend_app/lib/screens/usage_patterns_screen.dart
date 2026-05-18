import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';

class UsagePatternsScreen extends StatelessWidget {
  const UsagePatternsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF4A80F0);
    final bgColor = const Color(0xFFF8FAFF);
    final surfaceColor = Colors.white;
    final textColor = const Color(0xFF1A1C1E);

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: surfaceColor.withOpacity(0.7),
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryColor),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                "Usage Patterns",
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background decoration
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.05),
              ),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Interaction Analysis",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Track your engagement with StressCare",
                    style: TextStyle(
                      fontSize: 16,
                      color: textColor.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Daily Usage Card
                  _buildUsageCard(
                    context,
                    title: "Daily Usage",
                    subtitle: "Last 24 Hours",
                    value: "2h 15m",
                    percentage: "+12%",
                    icon: Icons.today_rounded,
                    color: Colors.blue,
                    chart: _buildDailyChart(),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Weekly Usage Card
                  _buildUsageCard(
                    context,
                    title: "Weekly Usage",
                    subtitle: "Last 7 Days",
                    value: "14h 40m",
                    percentage: "-5%",
                    icon: Icons.calendar_view_week_rounded,
                    color: Colors.indigo,
                    chart: _buildWeeklyChart(),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Monthly Usage Card
                  _buildUsageCard(
                    context,
                    title: "Monthly Usage",
                    subtitle: "Current Month",
                    value: "58h 20m",
                    percentage: "+8%",
                    icon: Icons.calendar_month_rounded,
                    color: Colors.deepPurple,
                    chart: _buildMonthlyChart(),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Yearly Usage Card
                  _buildUsageCard(
                    context,
                    title: "Yearly Usage",
                    subtitle: "Current Year",
                    value: "420h 15m",
                    percentage: "+15%",
                    icon: Icons.calendar_today_rounded,
                    color: Colors.amber,
                    chart: _buildYearlyChart(),
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String value,
    required String percentage,
    required IconData icon,
    required Color color,
    required Widget chart,
  }) {
    final textColor = const Color(0xFF1A1C1E);
    final isPositive = percentage.startsWith('+');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isPositive ? Colors.green : Colors.red).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  percentage,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  "Total time",
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 100,
            child: chart,
          ),
        ],
      ),
    );
  }

  Widget _buildDailyChart() {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 1),
              FlSpot(1, 1.5),
              FlSpot(2, 1.2),
              FlSpot(3, 2.5),
              FlSpot(4, 2),
              FlSpot(5, 3),
              FlSpot(6, 2.2),
            ],
            isCurved: true,
            color: Colors.blue,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart() {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: [
          _makeGroupData(0, 5, Colors.indigo),
          _makeGroupData(1, 6, Colors.indigo),
          _makeGroupData(2, 3, Colors.indigo),
          _makeGroupData(3, 7, Colors.indigo),
          _makeGroupData(4, 4, Colors.indigo),
          _makeGroupData(5, 8, Colors.indigo),
          _makeGroupData(6, 5, Colors.indigo),
        ],
      ),
    );
  }

  Widget _buildMonthlyChart() {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 3),
              FlSpot(1, 2),
              FlSpot(2, 5),
              FlSpot(3, 3),
              FlSpot(4, 4),
              FlSpot(5, 3),
              FlSpot(6, 6),
              FlSpot(7, 5),
              FlSpot(8, 7),
              FlSpot(9, 6),
              FlSpot(10, 8),
            ],
            isCurved: true,
            color: Colors.deepPurple,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.deepPurple.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearlyChart() {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 10),
              FlSpot(1, 15),
              FlSpot(2, 20),
              FlSpot(3, 18),
              FlSpot(4, 25),
              FlSpot(5, 30),
              FlSpot(6, 28),
              FlSpot(7, 35),
              FlSpot(8, 42),
              FlSpot(9, 38),
              FlSpot(10, 48),
              FlSpot(11, 55),
            ],
            isCurved: true,
            color: Colors.amber,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.amber.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _makeGroupData(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}
