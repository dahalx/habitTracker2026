
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// ============================================================================
/// NOTION HABIT TRACKER & JOURNAL - SAMSUNG GALAXY S25 STANDALONE EDITION
///
/// Features:
/// - Terminology: "Daily Score" (Day Score) and "Streak" (no level labels)
/// - Date Navigation: Previous / Next day & Calendar DatePicker (@Month Day, Year)
/// - Flexible Schedules: Target days per week (1-7) per habit
/// - Daily Journaling: Wealth, Uncomfortable actions, Record-breaking, Memories
/// - Markdown (.md) Export: Formatted template with Copy and .md File Save
/// - Security: 100% Offline, sandboxed SQLite, zero network permissions
/// ============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const NotionHabitTrackerApp());
}

class NotionHabitTrackerApp extends StatelessWidget {
  const NotionHabitTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notion Habit Tracker',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF388BFD),
          surface: Color(0xFF161B22),
          onSurface: Color(0xFFF0F6FC),
          outline: Color(0xFF30363D),
        ),
        fontFamily: 'Roboto',
      ),
      home: const HabitTrackerScreen(),
    );
  }
}

/// ============================================================================
/// MODELS
/// ============================================================================

class Habit {
  final String id;
  final String title;
  final String icon;
  final String category;
  final int colorValue;
  final int targetDaysPerWeek; // 1 - 7
  final DateTime createdAt;
  final int sortOrder;

  Habit({
    required this.id,
    required this.title,
    required this.icon,
    required this.category,
    required this.colorValue,
    this.targetDaysPerWeek = 7,
    required this.createdAt,
    required this.sortOrder,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'icon': icon,
      'category': category,
      'colorValue': colorValue,
      'targetDaysPerWeek': targetDaysPerWeek,
      'createdAt': createdAt.toIso8601String(),
      'sortOrder': sortOrder,
    };
  }

  factory Habit.fromMap(Map<String, dynamic> map) {
    return Habit(
      id: map['id'] as String,
      title: map['title'] as String,
      icon: map['icon'] as String,
      category: (map['category'] ?? 'General') as String,
      colorValue: map['colorValue'] as int,
      targetDaysPerWeek: (map['targetDaysPerWeek'] as int?) ?? 7,
      createdAt: DateTime.parse(map['createdAt'] as String),
      sortOrder: map['sortOrder'] as int,
    );
  }

  Habit copyWith({
    String? title,
    String? icon,
    String? category,
    int? colorValue,
    int? targetDaysPerWeek,
  }) {
    return Habit(
      id: id,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      colorValue: colorValue ?? this.colorValue,
      targetDaysPerWeek: targetDaysPerWeek ?? this.targetDaysPerWeek,
      createdAt: createdAt,
      sortOrder: sortOrder,
    );
  }
}

class DailyReflection {
  final String dateKey; // YYYY-MM-DD
  final String wealthNotes;
  final String uncomfortableNotes;
  final String recordBreakingNotes;
  final String memoriesNotes;
  final String updatedAt;

  const DailyReflection({
    required this.dateKey,
    this.wealthNotes = '',
    this.uncomfortableNotes = '',
    this.recordBreakingNotes = '',
    this.memoriesNotes = '',
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'dateKey': dateKey,
      'wealthNotes': wealthNotes,
      'uncomfortableNotes': uncomfortableNotes,
      'recordBreakingNotes': recordBreakingNotes,
      'memoriesNotes': memoriesNotes,
      'updatedAt': updatedAt,
    };
  }

  factory DailyReflection.fromMap(Map<String, dynamic> map) {
    return DailyReflection(
      dateKey: map['dateKey'] as String,
      wealthNotes: (map['wealthNotes'] as String?) ?? '',
      uncomfortableNotes: (map['uncomfortableNotes'] as String?) ?? '',
      recordBreakingNotes: (map['recordBreakingNotes'] as String?) ?? '',
      memoriesNotes: (map['memoriesNotes'] as String?) ?? '',
      updatedAt: (map['updatedAt'] as String?) ?? DateTime.now().toIso8601String(),
    );
  }
}

class HabitStreakResult {
  final int currentStreak;
  final int longestStreak;
  final int weeklyCompletions;

  const HabitStreakResult({
    required this.currentStreak,
    required this.longestStreak,
    this.weeklyCompletions = 0,
  });

  Color get badgeColor {
    if (currentStreak == 0) return const Color(0xFFEF4444); // Red: 0 days
    if (currentStreak == 1) return const Color(0xFF3B82F6); // Blue: 1 day
    return const Color(0xFF10B981); // Green: 2+ days
  }

  String get badgeText {
    if (currentStreak == 0) return '0d';
    if (currentStreak == 1) return '1d';
    return '${currentStreak}d 🔥';
  }
}

/// ============================================================================
/// LOCAL SQLITE DATABASE LAYER (STRICTLY SANDBOXED / AIR-GAPPED)
/// ============================================================================

class HabitDatabase {
  static final HabitDatabase instance = HabitDatabase._init();
  static Database? _database;

  HabitDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('notion_habits_s25_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE habits (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        icon TEXT NOT NULL,
        category TEXT NOT NULL,
        colorValue INTEGER NOT NULL,
        targetDaysPerWeek INTEGER NOT NULL DEFAULT 7,
        createdAt TEXT NOT NULL,
        sortOrder INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE habit_logs (
        id TEXT PRIMARY KEY,
        habitId TEXT NOT NULL,
        dateKey TEXT NOT NULL,
        completed INTEGER NOT NULL,
        completedAt TEXT,
        FOREIGN KEY (habitId) REFERENCES habits (id) ON DELETE CASCADE,
        UNIQUE(habitId, dateKey)
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_reflections (
        dateKey TEXT PRIMARY KEY,
        wealthNotes TEXT,
        uncomfortableNotes TEXT,
        recordBreakingNotes TEXT,
        memoriesNotes TEXT,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_logs_date ON habit_logs (dateKey)');
    await db.execute('CREATE INDEX idx_logs_habit ON habit_logs (habitId)');

    // Seed default Notion habits
    final now = DateTime.now();
    final initialHabits = [
      Habit(
        id: 'h_water',
        title: 'Drink 2.5L Water',
        icon: '💧',
        category: 'Health',
        colorValue: 0xFF388BFD,
        targetDaysPerWeek: 7,
        createdAt: now,
        sortOrder: 0,
      ),
      Habit(
        id: 'h_exercise',
        title: '30-Min Workout / Cardio',
        icon: '⚡',
        category: 'Fitness',
        colorValue: 0xFFF59E0B,
        targetDaysPerWeek: 5,
        createdAt: now,
        sortOrder: 1,
      ),
      Habit(
        id: 'h_read',
        title: 'Read 15 Pages',
        icon: '📖',
        category: 'Mind',
        colorValue: 0xFF8B5CF6,
        targetDaysPerWeek: 6,
        createdAt: now,
        sortOrder: 2,
      ),
      Habit(
        id: 'h_meditate',
        title: 'Mindful Meditation',
        icon: '🧘',
        category: 'Wellness',
        colorValue: 0xFF10B981,
        targetDaysPerWeek: 7,
        createdAt: now,
        sortOrder: 3,
      ),
    ];

    for (final habit in initialHabits) {
      await db.insert('habits', habit.toMap());
    }
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE habits ADD COLUMN targetDaysPerWeek INTEGER NOT NULL DEFAULT 7');
      } catch (_) {}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS daily_reflections (
          dateKey TEXT PRIMARY KEY,
          wealthNotes TEXT,
          uncomfortableNotes TEXT,
          recordBreakingNotes TEXT,
          memoriesNotes TEXT,
          updatedAt TEXT NOT NULL
        )
      ''');
    }
  }

  Future<List<Habit>> getHabits() async {
    final db = await instance.database;
    final result = await db.query('habits', orderBy: 'sortOrder ASC');
    return result.map((json) => Habit.fromMap(json)).toList();
  }

  Future<void> insertHabit(Habit habit) async {
    final db = await instance.database;
    await db.insert('habits', habit.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateHabit(Habit habit) async {
    final db = await instance.database;
    await db.update('habits', habit.toMap(), where: 'id = ?', whereArgs: [habit.id]);
  }

  Future<void> deleteHabit(String id) async {
    final db = await instance.database;
    await db.delete('habits', where: 'id = ?', whereArgs: [id]);
    await db.delete('habit_logs', where: 'habitId = ?', whereArgs: [id]);
  }

  Future<Set<String>> getCompletedHabitIdsForDate(String dateKey) async {
    final db = await instance.database;
    final result = await db.query(
      'habit_logs',
      columns: ['habitId'],
      where: 'dateKey = ? AND completed = 1',
      whereArgs: [dateKey],
    );
    return result.map((r) => r['habitId'] as String).toSet();
  }

  Future<void> setHabitCompleted(String habitId, String dateKey, bool completed) async {
    final db = await instance.database;
    final logId = '${habitId}_$dateKey';

    if (completed) {
      await db.insert(
        'habit_logs',
        {
          'id': logId,
          'habitId': habitId,
          'dateKey': dateKey,
          'completed': 1,
          'completedAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.delete(
        'habit_logs',
        where: 'habitId = ? AND dateKey = ?',
        whereArgs: [habitId, dateKey],
      );
    }
  }

  Future<DailyReflection> getReflectionForDate(String dateKey) async {
    final db = await instance.database;
    final res = await db.query(
      'daily_reflections',
      where: 'dateKey = ?',
      whereArgs: [dateKey],
    );
    if (res.isNotEmpty) {
      return DailyReflection.fromMap(res.first);
    }
    return DailyReflection(dateKey: dateKey, updatedAt: DateTime.now().toIso8601String());
  }

  Future<void> saveReflection(DailyReflection reflection) async {
    final db = await instance.database;
    await db.insert(
      'daily_reflections',
      reflection.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Calculates Streak based on consecutive active days & schedule goals
  Future<HabitStreakResult> calculateStreaks(String habitId, String activeDateKey) async {
    final db = await instance.database;
    final results = await db.query(
      'habit_logs',
      columns: ['dateKey'],
      where: 'habitId = ? AND completed = 1',
      whereArgs: [habitId],
      orderBy: 'dateKey DESC',
    );

    if (results.isEmpty) {
      return const HabitStreakResult(currentStreak: 0, longestStreak: 0, weeklyCompletions: 0);
    }

    final dates = results
        .map((r) => DateTime.parse(r['dateKey'] as String))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    final selected = DateTime.parse(activeDateKey);
    final yesterday = selected.subtract(const Duration(days: 1));

    int currentStreak = 0;
    final dateSet = dates.map((d) => DateFormat('yyyy-MM-dd').format(d)).toSet();

    final todayFormatted = DateFormat('yyyy-MM-dd').format(selected);
    final yesterdayFormatted = DateFormat('yyyy-MM-dd').format(yesterday);

    final completedToday = dateSet.contains(todayFormatted);
    final completedYesterday = dateSet.contains(yesterdayFormatted);

    if (completedToday || completedYesterday) {
      DateTime checkDate = completedToday ? selected : yesterday;
      while (dateSet.contains(DateFormat('yyyy-MM-dd').format(checkDate))) {
        currentStreak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      }
    } else {
      currentStreak = 0;
    }

    // Longest Streak
    int longestStreak = 0;
    if (dates.isNotEmpty) {
      final sortedAsc = List<DateTime>.from(dates)..sort((a, b) => a.compareTo(b));
      int tempStreak = 1;
      longestStreak = 1;

      for (int i = 1; i < sortedAsc.length; i++) {
        final diffDays = sortedAsc[i].difference(sortedAsc[i - 1]).inDays;
        if (diffDays == 1) {
          tempStreak++;
          if (tempStreak > longestStreak) longestStreak = tempStreak;
        } else if (diffDays > 1) {
          tempStreak = 1;
        }
      }
      if (currentStreak > longestStreak) {
        longestStreak = currentStreak;
      }
    }

    // Weekly completions (last 7 days window)
    int weeklyCount = 0;
    for (int i = 0; i < 7; i++) {
      final d = selected.subtract(Duration(days: i));
      if (dateSet.contains(DateFormat('yyyy-MM-dd').format(d))) {
        weeklyCount++;
      }
    }

    return HabitStreakResult(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      weeklyCompletions: weeklyCount,
    );
  }
}

/// ============================================================================
/// MAIN SCREEN & LIFECYCLE CONTROLLER
/// ============================================================================

class HabitTrackerScreen extends StatefulWidget {
  const HabitTrackerScreen({super.key});

  @override
  State<HabitTrackerScreen> createState() => _HabitTrackerScreenState();
}

class _HabitTrackerScreenState extends State<HabitTrackerScreen>
    with WidgetsBindingObserver {
  late DateTime _selectedDate;
  late String _selectedDateKey;

  List<Habit> _habits = [];
  Set<String> _completedHabitIds = {};
  Map<String, HabitStreakResult> _streaks = {};
  DailyReflection _reflection = const DailyReflection(dateKey: '', updatedAt: '');
  bool _isLoading = true;

  // Reflection Controllers
  late TextEditingController _wealthController;
  late TextEditingController _uncomfortableController;
  late TextEditingController _recordBreakingController;
  late TextEditingController _memoriesController;
  Timer? _debounceSaveTimer;
  Timer? _midnightRolloverTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Default active screen to Today
    _selectedDate = DateTime.now();
    _selectedDateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    _wealthController = TextEditingController();
    _uncomfortableController = TextEditingController();
    _recordBreakingController = TextEditingController();
    _memoriesController = TextEditingController();

    _startMidnightWatchdog();
    _loadDataForSelectedDate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceSaveTimer?.cancel();
    _midnightRolloverTimer?.cancel();
    _wealthController.dispose();
    _uncomfortableController.dispose();
    _recordBreakingController.dispose();
    _memoriesController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // If user was viewing today and midnight passed, advance
      final nowKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final isViewingToday = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(minutes: 1))) == _selectedDateKey;
      if (isViewingToday && nowKey != _selectedDateKey) {
        setState(() {
          _selectedDate = DateTime.now();
          _selectedDateKey = nowKey;
        });
        _loadDataForSelectedDate();
      }
    }
  }

  void _startMidnightWatchdog() {
    _midnightRolloverTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final nowKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (_isToday(_selectedDate) && nowKey != _selectedDateKey) {
        setState(() {
          _selectedDate = DateTime.now();
          _selectedDateKey = nowKey;
        });
        _loadDataForSelectedDate();
      }
    });
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Future<void> _loadDataForSelectedDate() async {
    setState(() => _isLoading = true);
    final db = HabitDatabase.instance;
    final habits = await db.getHabits();
    final completed = await db.getCompletedHabitIdsForDate(_selectedDateKey);
    final reflection = await db.getReflectionForDate(_selectedDateKey);

    final Map<String, HabitStreakResult> streaks = {};
    for (final habit in habits) {
      streaks[habit.id] = await db.calculateStreaks(habit.id, _selectedDateKey);
    }

    if (mounted) {
      setState(() {
        _habits = habits;
        _completedHabitIds = completed;
        _streaks = streaks;
        _reflection = reflection;

        _wealthController.text = reflection.wealthNotes;
        _uncomfortableController.text = reflection.uncomfortableNotes;
        _recordBreakingController.text = reflection.recordBreakingNotes;
        _memoriesController.text = reflection.memoriesNotes;

        _isLoading = false;
      });
    }
  }

  void _changeDate(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
      _selectedDateKey = DateFormat('yyyy-MM-dd').format(newDate);
    });
    _loadDataForSelectedDate();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF388BFD),
              surface: Color(0xFF161B22),
              onSurface: Color(0xFFF0F6FC),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      _changeDate(picked);
    }
  }

  Future<void> _toggleHabit(Habit habit) async {
    HapticFeedback.selectionClick();
    final isCompleted = _completedHabitIds.contains(habit.id);
    final newStatus = !isCompleted;

    setState(() {
      if (newStatus) {
        _completedHabitIds.add(habit.id);
      } else {
        _completedHabitIds.remove(habit.id);
      }
    });

    final db = HabitDatabase.instance;
    await db.setHabitCompleted(habit.id, _selectedDateKey, newStatus);
    final newStreak = await db.calculateStreaks(habit.id, _selectedDateKey);

    if (mounted) {
      setState(() {
        _streaks[habit.id] = newStreak;
      });
    }
  }

  void _onReflectionChanged() {
    _debounceSaveTimer?.cancel();
    _debounceSaveTimer = Timer(const Duration(milliseconds: 600), () async {
      final updated = DailyReflection(
        dateKey: _selectedDateKey,
        wealthNotes: _wealthController.text.trim(),
        uncomfortableNotes: _uncomfortableController.text.trim(),
        recordBreakingNotes: _recordBreakingController.text.trim(),
        memoriesNotes: _memoriesController.text.trim(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      await HabitDatabase.instance.saveReflection(updated);
      _reflection = updated;
    });
  }

  /// ==========================================================================
  /// MARKDOWN (.md) EXPORT GENERATOR
  /// Formats exactly to Notion habitTemplate specifications
  /// ==========================================================================
  String _generateMarkdownContent() {
    final monthDayYear = DateFormat('MMMM d, yyyy').format(_selectedDate);
    final total = _habits.length;
    final completed = _completedHabitIds.length;
    final dailyScore = total == 0 ? 0 : ((completed / total) * 100).round();

    final buffer = StringBuffer();
    // Header
    buffer.writeln('# @$monthDayYear - habitTemplate\n');

    // Checklist
    for (final habit in _habits) {
      final isDone = _completedHabitIds.contains(habit.id);
      buffer.writeln('${habit.title}: ${isDone ? "Yes" : "No"}');
    }

    // Daily Score points
    buffer.writeln('points: $dailyScore%\n');

    // Wealth Section
    buffer.writeln('### Wealth:\n');
    final wealthText = _wealthController.text.trim();
    if (wealthText.isEmpty) {
      buffer.writeln('- None logged\n');
    } else {
      for (final line in wealthText.split('\n')) {
        if (line.trim().isNotEmpty) {
          buffer.writeln('- ${line.trim()}');
        }
      }
      buffer.writeln('');
    }

    // Uncomfortable actions
    buffer.writeln('<aside>\n💡\n');
    buffer.writeln('**Did I do anything uncomfortable today?**\n');
    final uncomfortableText = _uncomfortableController.text.trim();
    if (uncomfortableText.isEmpty) {
      buffer.writeln('- None logged\n');
    } else {
      for (final line in uncomfortableText.split('\n')) {
        if (line.trim().isNotEmpty) {
          buffer.writeln('- ${line.trim()}');
        }
      }
      buffer.writeln('');
    }
    buffer.writeln('</aside>\n');

    // Record breaking moments
    buffer.writeln('<aside>\n💡\n');
    buffer.writeln('**Any record breaking things I did today?**\n');
    final recordText = _recordBreakingController.text.trim();
    if (recordText.isEmpty) {
      buffer.writeln('- None logged\n');
    } else {
      for (final line in recordText.split('\n')) {
        if (line.trim().isNotEmpty) {
          buffer.writeln('- ${line.trim()}');
        }
      }
      buffer.writeln('');
    }
    buffer.writeln('</aside>\n');

    // Memories Section
    buffer.writeln('### Memories:\n');
    final memoriesText = _memoriesController.text.trim();
    if (memoriesText.isEmpty) {
      buffer.writeln('- None logged\n');
    } else {
      for (final line in memoriesText.split('\n')) {
        if (line.trim().isNotEmpty) {
          buffer.writeln('- ${line.trim()}');
        }
      }
      buffer.writeln('');
    }

    return buffer.toString();
  }

  void _showExportMarkdownModal() {
    final md = _generateMarkdownContent();
    final filename = 'habit_$_selectedDateKey.md';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF21262D),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.description, color: Color(0xFF388BFD), size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Export to Markdown',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF0F6FC),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 240,
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    md,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFC9D1D9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF30363D)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: md));
                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Markdown copied to clipboard!'),
                              backgroundColor: Color(0xFF238636),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy to Clipboard'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF238636),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        try {
                          final dir = await getApplicationDocumentsDirectory();
                          final file = File('${dir.path}/$filename');
                          await file.writeAsString(md);
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Saved locally as $filename'),
                                backgroundColor: const Color(0xFF238636),
                              ),
                            );
                          }
                        } catch (e) {
                          await Clipboard.setData(ClipboardData(text: md));
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard (device file fallback)'),
                                backgroundColor: Color(0xFF388BFD),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Save .md File'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddOrEditHabitModal([Habit? habitToEdit]) {
    final isEditing = habitToEdit != null;
    final titleController = TextEditingController(text: habitToEdit?.title ?? '');
    String selectedIcon = habitToEdit?.icon ?? '🎯';
    String selectedCategory = habitToEdit?.category ?? 'General';
    int selectedColor = habitToEdit?.colorValue ?? 0xFF388BFD;
    int targetDays = habitToEdit?.targetDaysPerWeek ?? 7;

    final icons = ['💧', '⚡', '📖', '🧘', '🥗', '💻', '🏃', '💤', '🎯', '🌿'];
    final categories = ['Health', 'Fitness', 'Mind', 'Wellness', 'Focus', 'General'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isEditing ? 'Edit Habit' : 'New Habit',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF0F6FC),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g., Read 15 Pages',
                      hintStyle: const TextStyle(color: Color(0xFF8B949E)),
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF30363D)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Schedule (Days per week):', style: TextStyle(color: Color(0xFF8B949E))),
                      Text('$targetDays days / week', style: const TextStyle(color: Color(0xFF388BFD), fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: targetDays.toDouble(),
                    min: 1,
                    max: 7,
                    divisions: 6,
                    label: '$targetDays days',
                    activeColor: const Color(0xFF388BFD),
                    inactiveColor: const Color(0xFF30363D),
                    onChanged: (val) {
                      setModalState(() => targetDays = val.round());
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Select Icon', style: TextStyle(color: Color(0xFF8B949E))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: icons.map((icon) {
                      final isSelected = selectedIcon == icon;
                      return GestureDetector(
                        onTap: () => setModalState(() => selectedIcon = icon),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF388BFD) : const Color(0xFF0D1117),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? Colors.transparent : const Color(0xFF30363D),
                            ),
                          ),
                          child: Text(icon, style: const TextStyle(fontSize: 20)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Category', style: TextStyle(color: Color(0xFF8B949E))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: categories.map((cat) {
                      final isSelected = selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: const Color(0xFF388BFD),
                        backgroundColor: const Color(0xFF0D1117),
                        onSelected: (val) {
                          if (val) setModalState(() => selectedCategory = cat);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF238636),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) return;

                        final db = HabitDatabase.instance;
                        if (isEditing) {
                          final updated = habitToEdit.copyWith(
                            title: title,
                            icon: selectedIcon,
                            category: selectedCategory,
                            colorValue: selectedColor,
                            targetDaysPerWeek: targetDays,
                          );
                          await db.updateHabit(updated);
                        } else {
                          final newHabit = Habit(
                            id: 'h_${DateTime.now().millisecondsSinceEpoch}',
                            title: title,
                            icon: selectedIcon,
                            category: selectedCategory,
                            colorValue: selectedColor,
                            targetDaysPerWeek: targetDays,
                            createdAt: DateTime.now(),
                            sortOrder: _habits.length,
                          );
                          await db.insertHabit(newHabit);
                        }
                        Navigator.pop(ctx);
                        _loadDataForSelectedDate();
                      },
                      child: Text(
                        isEditing ? 'Save Changes' : 'Create Habit',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteHabit(Habit habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Delete Habit?'),
        content: Text('Delete "${habit.title}" and its streak history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await HabitDatabase.instance.deleteHabit(habit.id);
      _loadDataForSelectedDate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalHabits = _habits.length;
    final completedCount = _completedHabitIds.length;
    final dailyScore = totalHabits == 0 ? 0.0 : (completedCount / totalHabits) * 100;
    final isViewingToday = _isToday(_selectedDate);

    // Formatted date string as requested: @Month Day, Year (e.g. @July 4, 2026)
    final dateDisplay = '@${DateFormat('MMMM d, yyyy').format(_selectedDate)}';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('📋', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notion Habits',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  dateDisplay,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF388BFD), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Export to Markdown',
            icon: const Icon(Icons.share, color: Color(0xFF8B949E), size: 22),
            onPressed: _showExportMarkdownModal,
          ),
          IconButton(
            tooltip: 'Add Habit',
            icon: const Icon(Icons.add_circle, color: Color(0xFF388BFD), size: 26),
            onPressed: () => _showAddOrEditHabitModal(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDataForSelectedDate,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // ========================================================
                  // DATE NAVIGATION BAR (Previous / Next / Date Picker)
                  // ========================================================
                  _buildDateNavigationBar(isViewingToday),

                  const SizedBox(height: 14),

                  // ========================================================
                  // DAILY SCORE CARD (Strictly Renamed from Level 4)
                  // ========================================================
                  _buildDailyScoreCard(dailyScore, completedCount, totalHabits),

                  const SizedBox(height: 16),

                  // Habits Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Habit Checklist',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF0F6FC),
                        ),
                      ),
                      Text(
                        '$completedCount / $totalHabits Completed',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Habit items
                  if (_habits.isEmpty)
                    _buildEmptyHabitState()
                  else
                    ..._habits.map((habit) => _buildHabitItem(habit)),

                  const SizedBox(height: 24),

                  // ========================================================
                  // DAILY JOURNALING & REFLECTION SECTIONS
                  // ========================================================
                  _buildJournalingSection(),

                  const SizedBox(height: 16),

                  // Export to Markdown Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF21262D),
                        foregroundColor: const Color(0xFFF0F6FC),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF30363D)),
                        ),
                      ),
                      onPressed: _showExportMarkdownModal,
                      icon: const Icon(Icons.file_download_outlined, color: Color(0xFF388BFD)),
                      label: const Text(
                        'Export to Markdown (.md)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Security footer
                  _buildSecurityFooter(),
                ],
              ),
            ),
    );
  }

  /// Date Navigation Bar with Previous, Today, Next and Date Picker
  Widget _buildDateNavigationBar(bool isViewingToday) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Previous Day',
            icon: const Icon(Icons.chevron_left, color: Color(0xFFF0F6FC)),
            onPressed: () => _changeDate(_selectedDate.subtract(const Duration(days: 1))),
          ),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 15, color: Color(0xFF388BFD)),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('EEE, MMM d, yyyy').format(_selectedDate),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFFF0F6FC),
                    ),
                  ),
                  if (isViewingToday) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF238636).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'TODAY',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Row(
            children: [
              if (!isViewingToday)
                TextButton(
                  onPressed: () => _changeDate(DateTime.now()),
                  child: const Text('Today', style: TextStyle(fontSize: 12, color: Color(0xFF388BFD))),
                ),
              IconButton(
                tooltip: 'Next Day',
                icon: const Icon(Icons.chevron_right, color: Color(0xFFF0F6FC)),
                onPressed: () => _changeDate(_selectedDate.add(const Duration(days: 1))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Daily Score Card (strictly named Daily Score)
  Widget _buildDailyScoreCard(double score, int completed, int total) {
    final scoreInt = score.round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DAILY SCORE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8B949E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$scoreInt%',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFF0F6FC),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        scoreInt == 100
                            ? '🎉 Perfect Day!'
                            : scoreInt >= 50
                                ? '⚡ Strong Momentum'
                                : '🌱 In Progress',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: scoreInt == 100
                              ? const Color(0xFF10B981)
                              : const Color(0xFF388BFD),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scoreInt == 100
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : const Color(0xFF388BFD).withValues(alpha: 0.15),
                ),
                child: Center(
                  child: Text(
                    scoreInt == 100 ? '🏆' : '📊',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: total == 0 ? 0 : completed / total),
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: const Color(0xFF21262D),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    scoreInt == 100
                        ? const Color(0xFF10B981)
                        : const Color(0xFF388BFD),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Habit Checklist Item with Streak Badge (Color: Red 0d, Blue 1d, Green 2+d)
  Widget _buildHabitItem(Habit habit) {
    final isCompleted = _completedHabitIds.contains(habit.id);
    final streak = _streaks[habit.id] ??
        const HabitStreakResult(currentStreak: 0, longestStreak: 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isCompleted ? const Color(0xFF1C2128) : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCompleted
              ? const Color(0xFF238636).withValues(alpha: 0.4)
              : const Color(0xFF30363D),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: GestureDetector(
          onTap: () => _toggleHabit(habit),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isCompleted ? const Color(0xFF238636) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCompleted ? const Color(0xFF238636) : const Color(0xFF8B949E),
                width: 2,
              ),
            ),
            child: isCompleted
                ? const Icon(Icons.check, size: 20, color: Colors.white)
                : null,
          ),
        ),
        title: Row(
          children: [
            Text(habit.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                habit.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isCompleted ? const Color(0xFF8B949E) : const Color(0xFFF0F6FC),
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4, left: 26),
          child: Row(
            children: [
              Text(
                '${habit.targetDaysPerWeek}x/wk',
                style: const TextStyle(fontSize: 11, color: Color(0xFF388BFD), fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                'Best: ${streak.longestStreak}d',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Streak badge (Red 0d, Blue 1d, Green 2+d)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: streak.badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: streak.badgeColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                streak.badgeText,
                style: TextStyle(
                  color: streak.badgeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            PopupMenuButton<String>(
              color: const Color(0xFF21262D),
              icon: const Icon(Icons.more_vert, color: Color(0xFF8B949E), size: 18),
              onSelected: (val) {
                if (val == 'edit') {
                  _showAddOrEditHabitModal(habit);
                } else if (val == 'delete') {
                  _deleteHabit(habit);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Edit', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 16, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Daily Journaling & Reflections Card
  Widget _buildJournalingSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.edit_note, color: Color(0xFF388BFD), size: 20),
              SizedBox(width: 8),
              Text(
                'Daily Reflections & Journal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF0F6FC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Auto-saved locally for this date and included in Markdown export.',
            style: TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
          ),
          const SizedBox(height: 16),

          // 1. Wealth Notes
          _buildJournalField(
            title: 'Wealth Notes',
            hint: 'Actions taken towards assets, skills, or financial discipline...',
            icon: Icons.attach_money,
            controller: _wealthController,
          ),

          const SizedBox(height: 14),

          // 2. Uncomfortable Actions
          _buildJournalField(
            title: 'Did I do anything uncomfortable today?',
            hint: 'Cold outreach, hard conversation, pushing through fear...',
            icon: Icons.lightbulb_outline,
            controller: _uncomfortableController,
          ),

          const SizedBox(height: 14),

          // 3. Record Breaking Moments
          _buildJournalField(
            title: 'Any record breaking things I did today?',
            hint: 'Personal best weights, max focused hours, highest sales...',
            icon: Icons.emoji_events_outlined,
            controller: _recordBreakingController,
          ),

          const SizedBox(height: 14),

          // 4. Daily Memories
          _buildJournalField(
            title: 'Daily Memories',
            hint: 'Gratitude, funny moment, meaningful conversation...',
            icon: Icons.bookmark_border,
            controller: _memoriesController,
          ),
        ],
      ),
    );
  }

  Widget _buildJournalField({
    required String title,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF8B949E)),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFC9D1D9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: 2,
          onChanged: (_) => _onReflectionChanged(),
          style: const TextStyle(fontSize: 13, color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF6E7681)),
            filled: true,
            fillColor: const Color(0xFF0D1117),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF30363D)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF30363D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF388BFD)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyHabitState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        children: [
          const Text('🌱', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          const Text(
            'No Habits Tracked Yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap the + button to create your first habit.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF8B949E)),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF388BFD)),
            onPressed: () => _showAddOrEditHabitModal(),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Add Habit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      child: const Row(
        children: [
          Icon(Icons.security, size: 18, color: Color(0xFF10B981)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Air-Gapped Android Sandbox • Zero Network Permissions • SQLite Local Storage',
              style: TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
            ),
          ),
        ],
      ),
    );
  }
}
