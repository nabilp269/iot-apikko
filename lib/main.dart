import 'package:flutter/material.dart';
import 'screens/monitoring_home_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/notification_screen.dart';
import 'app_theme.dart';

void main() => runApp(const MonitoringIoTApp());

class MonitoringIoTApp extends StatelessWidget {
  const MonitoringIoTApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, mode, _) => MaterialApp(
      title: 'Monitoring IoT',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF3B82F6),
          secondary: const Color(0xFF10B981),
          surface: Colors.white,
          error: const Color(0xFFEF4444),
        ),
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        cardColor: const Color(0xFF162033),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF60A5FA), secondary: Color(0xFF34D399), surface: Color(0xFF162033), error: Color(0xFFF87171)),
        fontFamily: 'Roboto',
      ),
      themeMode: mode,
      home: const MainNavigation(),
      debugShowCheckedModeBanner: false,
    ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late final _pages = [
    MonitoringHomeScreen(onNavigate: _selectPage),
    const ScheduleScreen(),
    const NotificationScreen(),
  ];

  void _selectPage(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        currentIndex: _currentIndex,
        onTap: _selectPage,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF3B82F6),
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        selectedFontSize: 12,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Beranda'),
          BottomNavigationBarItem(icon: Icon(Icons.schedule), label: 'Jadwal Kirim'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Notifikasi'),
        ],
      ),
    );
  }
}
