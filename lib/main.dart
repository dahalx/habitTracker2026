
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

/// ============================================================================
/// NOTION-STYLE HABIT TRACKER & OBSIDIAN EXPORTER - GALAXY S25 STANDALONE EDITION
///
/// Features:
/// 1. Hive Local-First Storage (No external databases, zero network permissions)
/// 2. Interactive Obsidian Directory Picker (FilePicker.platform.getDirectoryPath())
/// 3. Notion-Style Monthly Database Table View & Page Detail Views
/// 4. Flexible Habit Property Types:
///    - Checkbox (Standard Yes/No)
///    - Multi-Select (e.g. Berries & Nuts: Blueberry, Blackberry, Walnut...)
///    - Text Input (Freeform notes/metrics)
/// 5. Clean & Minimal Markdown Export (Excludes unchecked, empty, or negative items)
/// ============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive in internal sandboxed application directory
  await Hive.initFlutter();

  // Open Hive persistent boxes
  await Hive.openBox('habits_box');
  await Hive.openBox('daily_entries_box');

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
      title: 'Notion Habit Database',
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
      home: const NotionDatabaseScreen(),
    );
  }
}

/// ============================================================================
/// DATA MODELS
/// ============================================================================

enum HabitPropertyType { checkbox, multiSelect, text }

class HabitProperty {
  final String id;
  final String title;
  final String icon;
  final String category;
  final HabitPropertyType type;
  final List<String> options; // For multi-select
  final int targetDaysPerWeek; // 1 - 7
  final int sortOrder;

  HabitProperty({
    required this.id,
    required this.title,
    required this.icon,
    required this.category,
    required this.type,
    this.options = const [],
    this.targetDaysPerWeek = 7,
    required this.sortOrder,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'icon': icon,
      'category': category,
      'type': type.name,
      'options': options,
      'targetDaysPerWeek': targetDaysPerWeek,
      'sortOrder': sortOrder,
    };
  }

  factory HabitProperty.fromMap(Map<dynamic, dynamic> map) {
    return HabitProperty(
      id: map['id'] as String,
      title: map['title'] as String,
      icon: map['icon'] as String,
      category: (map['category'] ?? 'General') as String,
      type: HabitPropertyType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => HabitPropertyType.checkbox,
      ),
      options: List<String>.from(map['options'] ?? []),
      targetDaysPerWeek: (map['targetDaysPerWeek'] as int?) ?? 7,
      sortOrder: (map['sortOrder'] as int?) ?? 0,
    );
  }
}

class DailyEntryData {
  final String dateKey; // YYYY-MM-DD
  final Map<String, bool> checkboxes;
  final Map<String, List<String>> multiSelects;
  final Map<String, String> textValues;
  final Map<String, String> reflections; // wealth, uncomfortable, recordBreaking, memories
  final String updatedAt;

  DailyEntryData({
    required this.dateKey,
    this.checkboxes = const {},
    this.multiSelects = const {},
    this.textValues = const {},
    this.reflections = const {},
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'dateKey': dateKey,
      'checkboxes': checkboxes,
      'multiSelects': multiSelects,
      'textValues': textValues,
      'reflections': reflections,
      'updatedAt': updatedAt,
    };
  }

  factory DailyEntryData.fromMap(Map<dynamic, dynamic> map) {
    return DailyEntryData(
      dateKey: map['dateKey'] as String,
      checkboxes: Map<String, bool>.from(map['checkboxes'] ?? {}),
      multiSelects: (map['multiSelects'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), List<String>.from(v ?? [])),
          ) ??
          {},
      textValues: Map<String, String>.from(map['textValues'] ?? {}),
      reflections: Map<String, String>.from(map['reflections'] ?? {}),
      updatedAt: map['updatedAt'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  DailyEntryData copyWith({
    Map<String, bool>? checkboxes,
    Map<String, List<String>>? multiSelects,
    Map<String, String>? textValues,
    Map<String, String>? reflections,
  }) {
    return DailyEntryData(
      dateKey: dateKey,
      checkboxes: checkboxes ?? this.checkboxes,
      multiSelects: multiSelects ?? this.multiSelects,
      textValues: textValues ?? this.textValues,
      reflections: reflections ?? this.reflections,
      updatedAt: DateTime.now().toIso8601String(),
    );
  }
}

/// ============================================================================
/// REPOSITORY & HIVE DATABASE CONTROLLER
/// ============================================================================

class HabitHiveRepository {
  static final HabitHiveRepository instance = HabitHiveRepository._init();
  HabitHiveRepository._init();

  Box get habitsBox => Hive.box('habits_box');
  Box get entriesBox => Hive.box('daily_entries_box');

  Future<void> ensureDefaultHabitsSeeded() async {
    if (habitsBox.isEmpty) {
      final defaultHabits = [
        HabitProperty(
          id: 'h_water',
          title: 'Drink 2.5L Water',
          icon: '💧',
          category: 'Health',
          type: HabitPropertyType.checkbox,
          targetDaysPerWeek: 7,
          sortOrder: 0,
        ),
        HabitProperty(
          id: 'h_workout',
          title: '30-Min Workout / Cardio',
          icon: '⚡',
          category: 'Fitness',
          type: HabitPropertyType.checkbox,
          targetDaysPerWeek: 5,
          sortOrder: 1,
        ),
        HabitProperty(
          id: 'h_berries_nuts',
          title: 'Berries & Nuts Ate',
          icon: '🫐',
          category: 'Nutrition',
          type: HabitPropertyType.multiSelect,
          options: ['Blueberry', 'Blackberry', 'Raspberry', 'Walnut', 'Chia Seeds', 'Almonds'],
          targetDaysPerWeek: 6,
          sortOrder: 2,
        ),
        HabitProperty(
          id: 'h_reading',
          title: 'Read 15 Pages',
          icon: '📖',
          category: 'Mind',
          type: HabitPropertyType.text,
          targetDaysPerWeek: 7,
          sortOrder: 3,
        ),
        HabitProperty(
          id: 'h_meditate',
          title: 'Mindful Meditation',
          icon: '🧘',
          category: 'Wellness',
          type: HabitPropertyType.checkbox,
          targetDaysPerWeek: 7,
          sortOrder: 4,
        ),
      ];

      for (var h in defaultHabits) {
        await habitsBox.put(h.id, h.toMap());
      }
    }
  }

  List<HabitProperty> getAllHabits() {
    final list = habitsBox.values
        .map((e) => HabitProperty.fromMap(e as Map))
        .toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Future<void> saveHabit(HabitProperty habit) async {
    await habitsBox.put(habit.id, habit.toMap());
  }

  Future<void> deleteHabit(String id) async {
    await habitsBox.delete(id);
  }

  DailyEntryData getEntryForDate(String dateKey) {
    final raw = entriesBox.get(dateKey);
    if (raw != null) {
      return DailyEntryData.fromMap(raw as Map);
    }
    return DailyEntryData(
      dateKey: dateKey,
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  Future<void> saveEntry(DailyEntryData entry) async {
    await entriesBox.put(entry.dateKey, entry.toMap());
  }

  List<String> getRecentDateKeys({int count = 14}) {
    final now = DateTime.now();
    return List.generate(count, (i) {
      final d = now.subtract(Duration(days: i));
      return DateFormat('yyyy-MM-dd').format(d);
    });
  }

  /// Calculates Daily Score % for a given entry
  int calculateDailyScore(List<HabitProperty> habits, DailyEntryData entry) {
    if (habits.isEmpty) return 0;
    int completed = 0;
    for (var h in habits) {
      if (h.type == HabitPropertyType.checkbox) {
        if (entry.checkboxes[h.id] == true) completed++;
      } else if (h.type == HabitPropertyType.multiSelect) {
        final list = entry.multiSelects[h.id];
        if (list != null && list.isNotEmpty) completed++;
      } else if (h.type == HabitPropertyType.text) {
        final txt = entry.textValues[h.id];
        if (txt != null && txt.trim().isNotEmpty) completed++;
      }
    }
    return ((completed / habits.length) * 100).round();
  }
}

/// ============================================================================
/// NOTION DATABASE SCREEN: DUAL VIEW (DAILY PAGE VIEW vs MONTHLY TABLE VIEW)
/// ============================================================================

class NotionDatabaseScreen extends StatefulWidget {
  const NotionDatabaseScreen({super.key});

  @override
  State<NotionDatabaseScreen> createState() => _NotionDatabaseScreenState();
}

class _NotionDatabaseScreenState extends State<NotionDatabaseScreen> {
  int _selectedViewIndex = 0; // 0 = Daily Page View, 1 = Monthly Table View
  late String _activeDateKey;
  late DateTime _activeDate;
  List<HabitProperty> _habits = [];
  late DailyEntryData _currentEntry;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _activeDate = DateTime.now();
    _activeDateKey = DateFormat('yyyy-MM-dd').format(_activeDate);
    _initData();
  }

  Future<void> _initData() async {
    await HabitHiveRepository.instance.ensureDefaultHabitsSeeded();
    _loadState();
  }

  void _loadState() {
    setState(() {
      _habits = HabitHiveRepository.instance.getAllHabits();
      _currentEntry = HabitHiveRepository.instance.getEntryForDate(_activeDateKey);
      _isLoading = false;
    });
  }

  void _changeDate(DateTime date) {
    setState(() {
      _activeDate = date;
      _activeDateKey = DateFormat('yyyy-MM-dd').format(date);
      _currentEntry = HabitHiveRepository.instance.getEntryForDate(_activeDateKey);
    });
  }

  String _formatNotionDateHeader(DateTime d) {
    final dayName = DateFormat('EEEE').format(d);
    return '@${d.month}.${d.day}.${d.year}-$dayName';
  }

  /// ==========================================================================
  /// 1 & 4: CLEAN & MINIMAL OBSIDIAN MARKDOWN EXPORT ENGINE
  /// - Uses FilePicker.platform.getDirectoryPath() to select folder (Obsidian vault)
  /// - Excludes unchecked, empty, or negative items
  /// ==========================================================================
  String _generateMinimalMarkdown(DateTime date, DailyEntryData entry) {
    final notionTitle = _formatNotionDateHeader(date);
    final score = HabitHiveRepository.instance.calculateDailyScore(_habits, entry);

    final buffer = StringBuffer();
    // 1. Clean Obsidian YAML Frontmatter
    buffer.writeln('---');
    buffer.writeln('date: ${DateFormat('yyyy-MM-dd').format(date)}');
    buffer.writeln('day: ${DateFormat('EEEE').format(date)}');
    buffer.writeln('score: $score%');
    buffer.writeln('tags:');
    buffer.writeln('  - habit-tracker');
    buffer.writeln('  - daily-log');
    buffer.writeln('---\n');

    // 2. Notion-Style Title
    buffer.writeln('# $notionTitle\n');

    // 3. Completed Habits ONLY
    final completedItems = <String>[];
    for (var habit in _habits) {
      if (habit.type == HabitPropertyType.checkbox) {
        if (entry.checkboxes[habit.id] == true) {
          completedItems.add('- [x] ${habit.title}');
        }
      } else if (habit.type == HabitPropertyType.multiSelect) {
        final selected = entry.multiSelects[habit.id];
        if (selected != null && selected.isNotEmpty) {
          final subList = selected.map((s) => '  - $s').join('\n');
          completedItems.add('- [x] ${habit.title}:\n$subList');
        }
      } else if (habit.type == HabitPropertyType.text) {
        final textVal = entry.textValues[habit.id];
        if (textVal != null && textVal.trim().isNotEmpty) {
          completedItems.add('- [x] ${habit.title}: ${textVal.trim()}');
        }
      }
    }

    if (completedItems.isNotEmpty) {
      buffer.writeln('## Habits Completed\n');
      for (var item in completedItems) {
        buffer.writeln(item);
      }
      buffer.writeln('');
    }

    // 4. Non-Empty Reflections ONLY
    final wealth = entry.reflections['wealth']?.trim();
    final uncomfortable = entry.reflections['uncomfortable']?.trim();
    final recordBreaking = entry.reflections['recordBreaking']?.trim();
    final memories = entry.reflections['memories']?.trim();

    final hasReflections = (wealth?.isNotEmpty ?? false) ||
        (uncomfortable?.isNotEmpty ?? false) ||
        (recordBreaking?.isNotEmpty ?? false) ||
        (memories?.isNotEmpty ?? false);

    if (hasReflections) {
      buffer.writeln('## Reflections\n');

      if (wealth != null && wealth.isNotEmpty) {
        buffer.writeln('### Wealth\n');
        for (var line in wealth.split('\n')) {
          if (line.trim().isNotEmpty) buffer.writeln('- ${line.trim()}');
        }
        buffer.writeln('');
      }

      if (uncomfortable != null && uncomfortable.isNotEmpty) {
        buffer.writeln('<aside>\n💡\n');
        buffer.writeln('**Did I do anything uncomfortable today?**\n');
        for (var line in uncomfortable.split('\n')) {
          if (line.trim().isNotEmpty) buffer.writeln('- ${line.trim()}');
        }
        buffer.writeln('\n</aside>\n');
      }

      if (recordBreaking != null && recordBreaking.isNotEmpty) {
        buffer.writeln('<aside>\n💡\n');
        buffer.writeln('**Any record breaking things I did today?**\n');
        for (var line in recordBreaking.split('\n')) {
          if (line.trim().isNotEmpty) buffer.writeln('- ${line.trim()}');
        }
        buffer.writeln('\n</aside>\n');
      }

      if (memories != null && memories.isNotEmpty) {
        buffer.writeln('### Memories\n');
        for (var line in memories.split('\n')) {
          if (line.trim().isNotEmpty) buffer.writeln('- ${line.trim()}');
        }
        buffer.writeln('');
      }
    }

    return buffer.toString().trimRight();
  }

  Future<void> _exportToObsidianVault() async {
    final mdContent = _generateMinimalMarkdown(_activeDate, _currentEntry);
    final filename = '${_activeDateKey}.md';

    try {
      // Feature 1: Prompt user for destination directory using file_picker
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select your Obsidian Vault or Target Folder',
      );

      if (selectedDirectory != null) {
        final filePath = '$selectedDirectory/$filename';
        final file = File(filePath);
        await file.writeAsString(mdContent);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to Obsidian: $filename'),
              backgroundColor: const Color(0xFF238636),
              action: SnackBarAction(
                label: 'Copy Text',
                textColor: Colors.white,
                onPressed: () => Clipboard.setData(ClipboardData(text: mdContent)),
              ),
            ),
          );
        }
      } else {
        // Fallback option to copy directly if user cancelled directory picker
        _showCopyMarkdownSheet(mdContent);
      }
    } catch (e) {
      _showCopyMarkdownSheet(mdContent);
    }
  }

  void _showCopyMarkdownSheet(String mdContent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Obsidian Clean Markdown Preview',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Container(
              height: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  mdContent,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFC9D1D9)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: mdContent));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Markdown copied to clipboard!')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16, color: Colors.white),
                label: const Text('Copy to Clipboard', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
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
                  'Notion Habit Database',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  _formatNotionDateHeader(_activeDate),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF388BFD), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Export to Obsidian Folder',
            icon: const Icon(Icons.folder_zip_outlined, color: Color(0xFF388BFD)),
            onPressed: _exportToObsidianVault,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedViewIndex = 0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selectedViewIndex == 0 ? const Color(0xFF388BFD) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.article_outlined, size: 14, color: _selectedViewIndex == 0 ? Colors.white : Colors.grey),
                            const SizedBox(width: 6),
                            Text(
                              'Daily Page',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _selectedViewIndex == 0 ? Colors.white : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedViewIndex = 1),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selectedViewIndex == 1 ? const Color(0xFF388BFD) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.table_chart_outlined, size: 14, color: _selectedViewIndex == 1 ? Colors.white : Colors.grey),
                            const SizedBox(width: 6),
                            Text(
                              'Monthly Table',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _selectedViewIndex == 1 ? Colors.white : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _selectedViewIndex == 0 ? _buildDailyPageView() : _buildMonthlyTableView(),
    );
  }

  /// ==========================================================================
  /// 2b: NOTION PAGE DETAIL VIEW
  /// ==========================================================================
  Widget _buildDailyPageView() {
    final score = HabitHiveRepository.instance.calculateDailyScore(_habits, _currentEntry);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Date Switcher Header
        _buildDateHeaderBar(),

        const SizedBox(height: 14),

        // Score Card
        Container(
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
                        style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Color(0xFF8B949E)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$score%',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFFF0F6FC)),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: score == 100 ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF388BFD).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text(score == 100 ? '🏆' : '📊', style: const TextStyle(fontSize: 20)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: score / 100,
                  minHeight: 8,
                  backgroundColor: const Color(0xFF21262D),
                  valueColor: AlwaysStoppedAnimation<Color>(score == 100 ? const Color(0xFF10B981) : const Color(0xFF388BFD)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Notion Page Property List
        const Text(
          'Properties',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFF0F6FC)),
        ),
        const SizedBox(height: 8),

        ..._habits.map((habit) => _buildHabitPropertyTile(habit)),

        const SizedBox(height: 20),

        // Reflections / Notes
        _buildReflectionsEditor(),

        const SizedBox(height: 16),

        // Export Button
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF238636),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _exportToObsidianVault,
          icon: const Icon(Icons.folder_shared, size: 18),
          label: const Text('Export Day to Obsidian Vault (.md)', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildDateHeaderBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: () => _changeDate(_activeDate.subtract(const Duration(days: 1))),
          ),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _activeDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (picked != null) _changeDate(picked);
            },
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: Color(0xFF388BFD)),
                const SizedBox(width: 8),
                Text(
                  _formatNotionDateHeader(_activeDate),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFF0F6FC)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: () => _changeDate(_activeDate.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitPropertyTile(HabitProperty habit) {
    if (habit.type == HabitPropertyType.checkbox) {
      final isChecked = _currentEntry.checkboxes[habit.id] ?? false;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isChecked ? const Color(0xFF238636) : const Color(0xFF30363D)),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isChecked,
              activeColor: const Color(0xFF238636),
              onChanged: (val) {
                final updated = Map<String, bool>.from(_currentEntry.checkboxes);
                updated[habit.id] = val ?? false;
                final newEntry = _currentEntry.copyWith(checkboxes: updated);
                HabitHiveRepository.instance.saveEntry(newEntry);
                setState(() => _currentEntry = newEntry);
              },
            ),
            Text(habit.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                habit.title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isChecked ? Colors.grey : Colors.white,
                  decoration: isChecked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${habit.targetDaysPerWeek}x/wk', style: const TextStyle(fontSize: 10, color: Color(0xFF8B949E))),
            ),
          ],
        ),
      );
    } else if (habit.type == HabitPropertyType.multiSelect) {
      final selected = _currentEntry.multiSelects[habit.id] ?? [];
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(habit.icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(habit.title, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                TextButton.icon(
                  onPressed: () => _showMultiSelectPicker(habit),
                  icon: const Icon(Icons.edit, size: 14, color: Color(0xFF388BFD)),
                  label: const Text('Edit', style: TextStyle(fontSize: 12, color: Color(0xFF388BFD))),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: selected.isEmpty
                  ? [
                      GestureDetector(
                        onTap: () => _showMultiSelectPicker(habit),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1117),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF30363D)),
                          ),
                          child: const Text('+ Select options...', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ),
                      ),
                    ]
                  : selected.map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF388BFD).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF388BFD).withValues(alpha: 0.4)),
                        ),
                        child: Text(item, style: const TextStyle(fontSize: 11, color: Color(0xFF58A6FF))),
                      );
                    }).toList(),
            ),
          ],
        ),
      );
    } else {
      // Freeform Text property
      final textVal = _currentEntry.textValues[habit.id] ?? '';
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(habit.icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(habit.title, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextFormField(
              initialValue: textVal,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter notes or metrics...',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
              ),
              onChanged: (val) {
                final updated = Map<String, String>.from(_currentEntry.textValues);
                updated[habit.id] = val;
                final newEntry = _currentEntry.copyWith(textValues: updated);
                HabitHiveRepository.instance.saveEntry(newEntry);
                setState(() => _currentEntry = newEntry);
              },
            ),
          ],
        ),
      );
    }
  }

  void _showMultiSelectPicker(HabitProperty habit) {
    final currentSelected = List<String>.from(_currentEntry.multiSelects[habit.id] ?? []);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select for ${habit.title}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: habit.options.map((option) {
                      final isSelected = currentSelected.contains(option);
                      return FilterChip(
                        label: Text(option),
                        selected: isSelected,
                        selectedColor: const Color(0xFF388BFD),
                        onSelected: (val) {
                          setModalState(() {
                            if (val) {
                              currentSelected.add(option);
                            } else {
                              currentSelected.remove(option);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
                      onPressed: () {
                        final updated = Map<String, List<String>>.from(_currentEntry.multiSelects);
                        updated[habit.id] = currentSelected;
                        final newEntry = _currentEntry.copyWith(multiSelects: updated);
                        HabitHiveRepository.instance.saveEntry(newEntry);
                        setState(() => _currentEntry = newEntry);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Save Selection', style: TextStyle(color: Colors.white)),
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

  Widget _buildReflectionsEditor() {
    final wealth = _currentEntry.reflections['wealth'] ?? '';
    final uncomfortable = _currentEntry.reflections['uncomfortable'] ?? '';
    final recordBreaking = _currentEntry.reflections['recordBreaking'] ?? '';
    final memories = _currentEntry.reflections['memories'] ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Daily Journal & Reflections', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          _buildReflectField('Wealth Notes', wealth, (val) => _updateReflection('wealth', val)),
          _buildReflectField('Did I do anything uncomfortable today?', uncomfortable, (val) => _updateReflection('uncomfortable', val)),
          _buildReflectField('Any record breaking things I did today?', recordBreaking, (val) => _updateReflection('recordBreaking', val)),
          _buildReflectField('Daily Memories', memories, (val) => _updateReflection('memories', val)),
        ],
      ),
    );
  }

  Widget _buildReflectField(String label, String value, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: value,
            maxLines: 2,
            style: const TextStyle(fontSize: 12, color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF0D1117),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  void _updateReflection(String key, String val) {
    final updated = Map<String, String>.from(_currentEntry.reflections);
    updated[key] = val;
    final newEntry = _currentEntry.copyWith(reflections: updated);
    HabitHiveRepository.instance.saveEntry(newEntry);
    _currentEntry = newEntry;
  }

  /// ==========================================================================
  /// 2a: NOTION-STYLE MONTHLY DATABASE TABLE VIEW
  /// ==========================================================================
  Widget _buildMonthlyTableView() {
    final dates = HabitHiveRepository.instance.getRecentDateKeys(count: 30);

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF161B22)),
          dataRowColor: WidgetStateProperty.all(const Color(0xFF0D1117)),
          horizontalMargin: 12,
          columnSpacing: 16,
          columns: [
            const DataColumn(label: Text('Date Page', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
            const DataColumn(label: Text('Score %', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
            ..._habits.map((h) => DataColumn(
                  label: Row(
                    children: [
                      Text(h.icon),
                      const SizedBox(width: 4),
                      Text(h.title, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                )),
          ],
          rows: dates.map((dateKey) {
            final entry = HabitHiveRepository.instance.getEntryForDate(dateKey);
            final d = DateTime.parse(dateKey);
            final formatted = _formatNotionDateHeader(d);
            final score = HabitHiveRepository.instance.calculateDailyScore(_habits, entry);

            return DataRow(
              cells: [
                // Date page button (opens day in Page View)
                DataCell(
                  InkWell(
                    onTap: () {
                      _changeDate(d);
                      setState(() => _selectedViewIndex = 0);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.open_in_new, size: 14, color: Color(0xFF388BFD)),
                        const SizedBox(width: 6),
                        Text(
                          formatted,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF58A6FF)),
                        ),
                      ],
                    ),
                  ),
                ),
                // Score Badge
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: score == 100
                          ? const Color(0xFF238636).withValues(alpha: 0.3)
                          : const Color(0xFF388BFD).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$score%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ),
                // Habit cells
                ..._habits.map((habit) {
                  if (habit.type == HabitPropertyType.checkbox) {
                    final done = entry.checkboxes[habit.id] ?? false;
                    return DataCell(
                      Icon(
                        done ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 16,
                        color: done ? const Color(0xFF238636) : Colors.grey,
                      ),
                    );
                  } else if (habit.type == HabitPropertyType.multiSelect) {
                    final selected = entry.multiSelects[habit.id] ?? [];
                    return DataCell(
                      Text(
                        selected.isEmpty ? '-' : selected.join(', '),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
                      ),
                    );
                  } else {
                    final txt = entry.textValues[habit.id] ?? '';
                    return DataCell(
                      Text(
                        txt.isEmpty ? '-' : txt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
                      ),
                    );
                  }
                }),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
