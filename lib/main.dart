
import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

/// ============================================================================
/// NOTION-STYLE HABIT TRACKER & OBSIDIAN EXPORTER - WEB & MOBILE READY
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
  final int targetDaysPerWeek;
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
  final Map<String, String> reflections;
  final List<HabitProperty>? dayHabits; // Day-specific habit override
  final String updatedAt;

  DailyEntryData({
    required this.dateKey,
    this.checkboxes = const {},
    this.multiSelects = const {},
    this.textValues = const {},
    this.reflections = const {},
    this.dayHabits,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'dateKey': dateKey,
      'checkboxes': checkboxes,
      'multiSelects': multiSelects,
      'textValues': textValues,
      'reflections': reflections,
      'dayHabits': dayHabits?.map((h) => h.toMap()).toList(),
      'updatedAt': updatedAt,
    };
  }

  factory DailyEntryData.fromMap(Map<dynamic, dynamic> map) {
    List<HabitProperty>? parsedDayHabits;
    if (map['dayHabits'] != null) {
      parsedDayHabits = (map['dayHabits'] as List)
          .map((e) => HabitProperty.fromMap(e as Map))
          .toList();
    }

    return DailyEntryData(
      dateKey: map['dateKey'] as String,
      checkboxes: Map<String, bool>.from(map['checkboxes'] ?? {}),
      multiSelects: (map['multiSelects'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), List<String>.from(v ?? [])),
          ) ??
          {},
      textValues: Map<String, String>.from(map['textValues'] ?? {}),
      reflections: Map<String, String>.from(map['reflections'] ?? {}),
      dayHabits: parsedDayHabits,
      updatedAt: map['updatedAt'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  DailyEntryData copyWith({
    Map<String, bool>? checkboxes,
    Map<String, List<String>>? multiSelects,
    Map<String, String>? textValues,
    Map<String, String>? reflections,
    List<HabitProperty>? dayHabits,
  }) {
    return DailyEntryData(
      dateKey: dateKey,
      checkboxes: checkboxes ?? this.checkboxes,
      multiSelects: multiSelects ?? this.multiSelects,
      textValues: textValues ?? this.textValues,
      reflections: reflections ?? this.reflections,
      dayHabits: dayHabits ?? this.dayHabits,
      updatedAt: DateTime.now().toIso8601String(),
    );
  }
}

/// ============================================================================
/// REPOSITORY & DATABASE CONTROLLER
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
      ];

      for (var h in defaultHabits) {
        await habitsBox.put(h.id, h.toMap());
      }
    }
  }

  List<HabitProperty> getAllTemplateHabits() {
    final list = habitsBox.values
        .map((e) => HabitProperty.fromMap(e as Map))
        .toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Future<void> saveTemplateHabit(HabitProperty habit) async {
    await habitsBox.put(habit.id, habit.toMap());
  }

  Future<void> deleteTemplateHabit(String id) async {
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

  List<HabitProperty> getActiveHabitsForDate(DailyEntryData entry) {
    if (entry.dayHabits != null && entry.dayHabits!.isNotEmpty) {
      return entry.dayHabits!;
    }
    return getAllTemplateHabits();
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
/// NOTION DATABASE SCREEN
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
  late DailyEntryData _currentEntry;
  List<HabitProperty> _activeHabits = [];
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
      _currentEntry = HabitHiveRepository.instance.getEntryForDate(_activeDateKey);
      _activeHabits = HabitHiveRepository.instance.getActiveHabitsForDate(_currentEntry);
      _isLoading = false;
    });
  }

  void _changeDate(DateTime date) {
    setState(() {
      _activeDate = date;
      _activeDateKey = DateFormat('yyyy-MM-dd').format(date);
      _currentEntry = HabitHiveRepository.instance.getEntryForDate(_activeDateKey);
      _activeHabits = HabitHiveRepository.instance.getActiveHabitsForDate(_currentEntry);
    });
  }

  String _formatNotionDateHeader(DateTime d) {
    final dayName = DateFormat('EEEE').format(d);
    return '@${d.month}.${d.day}.${d.year}-$dayName';
  }

  String _generateMinimalMarkdown(DateTime date, DailyEntryData entry, List<HabitProperty> habits) {
    final notionTitle = _formatNotionDateHeader(date);
    final score = HabitHiveRepository.instance.calculateDailyScore(habits, entry);

    final buffer = StringBuffer();
    buffer.writeln('---');
    buffer.writeln('date: ${DateFormat('yyyy-MM-dd').format(date)}');
    buffer.writeln('day: ${DateFormat('EEEE').format(date)}');
    buffer.writeln('score: $score%');
    buffer.writeln('tags:');
    buffer.writeln('  - habit-tracker');
    buffer.writeln('  - daily-log');
    buffer.writeln('---\n');

    buffer.writeln('# $notionTitle\n');

    final completedItems = <String>[];
    for (var habit in habits) {
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

    return buffer.toString().trimRight();
  }

  Future<void> _exportToObsidianVault() async {
    final mdContent = _generateMinimalMarkdown(_activeDate, _currentEntry, _activeHabits);
    final filename = '$_activeDateKey.md';

    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Obsidian Note',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['md', 'txt'],
        bytes: Uint8List.fromList(utf8.encode(mdContent)),
      );

      if (outputFile != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to Obsidian: $filename'),
            backgroundColor: const Color(0xFF238636),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showHabitEditorDialog({HabitProperty? existingHabit}) {
    final isEditing = existingHabit != null;
    final titleController = TextEditingController(text: existingHabit?.title ?? '');
    final iconController = TextEditingController(text: existingHabit?.icon ?? '🎯');
    final optionsController = TextEditingController(text: existingHabit?.options.join(', ') ?? '');
    HabitPropertyType selectedType = existingHabit?.type ?? HabitPropertyType.checkbox;

    bool applyToThisDayOnly = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isEditing ? 'Edit Habit' : 'Create New Habit',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      if (isEditing)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          tooltip: 'Delete Habit',
                          onPressed: () => _confirmDeleteHabit(existingHabit, applyToThisDayOnly, ctx),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: iconController,
                          decoration: const InputDecoration(
                            labelText: 'Icon',
                            filled: true,
                            fillColor: Color(0xFF0D1117),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: titleController,
                          decoration: const InputDecoration(
                            labelText: 'Habit Name',
                            hintText: 'e.g. Read Book',
                            filled: true,
                            fillColor: Color(0xFF0D1117),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<HabitPropertyType>(
                    initialValue: selectedType,
                    dropdownColor: const Color(0xFF161B22),
                    decoration: const InputDecoration(
                      labelText: 'Property Type',
                      filled: true,
                      fillColor: Color(0xFF0D1117),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: HabitPropertyType.checkbox,
                        child: Text('Checkbox (Yes/No)'),
                      ),
                      DropdownMenuItem(
                        value: HabitPropertyType.multiSelect,
                        child: Text('Multi-Select (Tags/Options)'),
                      ),
                      DropdownMenuItem(
                        value: HabitPropertyType.text,
                        child: Text('Text Input (Notes/Value)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedType = val);
                      }
                    },
                  ),
                  if (selectedType == HabitPropertyType.multiSelect) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: optionsController,
                      decoration: const InputDecoration(
                        labelText: 'Options (comma separated)',
                        hintText: 'e.g. Blueberry, Walnut, Almonds',
                        filled: true,
                        fillColor: Color(0xFF0D1117),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        applyToThisDayOnly ? 'Apply to This Day Only ($_activeDateKey)' : 'Apply to Master Template (Default for All New Days)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      subtitle: Text(
                        applyToThisDayOnly ? 'Will NOT affect past or future days.' : 'Updates default list for uncustomized days.',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      value: applyToThisDayOnly,
                      activeColor: const Color(0xFF388BFD),
                      onChanged: (val) {
                        setModalState(() => applyToThisDayOnly = val);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF238636),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) return;

                        final options = optionsController.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();

                        final habitToSave = HabitProperty(
                          id: existingHabit?.id ?? 'h_${DateTime.now().millisecondsSinceEpoch}',
                          title: title,
                          icon: iconController.text.trim().isEmpty ? '🎯' : iconController.text.trim(),
                          category: existingHabit?.category ?? 'Custom',
                          type: selectedType,
                          options: options,
                          targetDaysPerWeek: existingHabit?.targetDaysPerWeek ?? 7,
                          sortOrder: existingHabit?.sortOrder ?? _activeHabits.length,
                        );

                        if (applyToThisDayOnly) {
                          final currentList = List<HabitProperty>.from(_activeHabits);
                          if (isEditing) {
                            final idx = currentList.indexWhere((h) => h.id == habitToSave.id);
                            if (idx != -1) currentList[idx] = habitToSave;
                          } else {
                            currentList.add(habitToSave);
                          }
                          final newEntry = _currentEntry.copyWith(dayHabits: currentList);
                          await HabitHiveRepository.instance.saveEntry(newEntry);
                        } else {
                          await HabitHiveRepository.instance.saveTemplateHabit(habitToSave);
                        }

                        _loadState();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(
                        isEditing ? 'Save Changes' : 'Create Habit',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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

  void _confirmDeleteHabit(HabitProperty habit, bool applyToThisDayOnly, BuildContext modalCtx) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Delete Habit', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${habit.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (applyToThisDayOnly) {
                final currentList = List<HabitProperty>.from(_activeHabits);
                currentList.removeWhere((h) => h.id == habit.id);
                final newEntry = _currentEntry.copyWith(dayHabits: currentList);
                await HabitHiveRepository.instance.saveEntry(newEntry);
              } else {
                await HabitHiveRepository.instance.deleteTemplateHabit(habit.id);
              }

              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (modalCtx.mounted) Navigator.pop(modalCtx);
              _loadState();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
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
            tooltip: 'Export Day to Obsidian (.md)',
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showHabitEditorDialog(),
        backgroundColor: const Color(0xFF388BFD),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add / Customize Habit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildDailyPageView() {
    final score = HabitHiveRepository.instance.calculateDailyScore(_activeHabits, _currentEntry);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _buildDateHeaderBar(),
        const SizedBox(height: 14),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _currentEntry.dayHabits != null ? 'Habits (Customized for Today)' : 'Habits (Default Template)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFF0F6FC)),
            ),
            if (_currentEntry.dayHabits != null)
              TextButton(
                onPressed: () async {
                  final newEntry = _currentEntry.copyWith(dayHabits: null);
                  await HabitHiveRepository.instance.saveEntry(newEntry);
                  _loadState();
                },
                child: const Text('Reset to Template', style: TextStyle(fontSize: 11, color: Colors.orangeAccent)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ..._activeHabits.map((habit) => _buildHabitPropertyTile(habit)),
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
              if (habit.type == HabitPropertyType.checkbox)
                Checkbox(
                  value: _currentEntry.checkboxes[habit.id] ?? false,
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
                    color: (_currentEntry.checkboxes[habit.id] ?? false) ? Colors.grey : Colors.white,
                    decoration: (_currentEntry.checkboxes[habit.id] ?? false) ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF8B949E)),
                tooltip: 'Edit / Delete Habit',
                onPressed: () => _showHabitEditorDialog(existingHabit: habit),
              ),
            ],
          ),
          if (habit.type == HabitPropertyType.multiSelect) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...(_currentEntry.multiSelects[habit.id] ?? []).map((item) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF388BFD).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF388BFD).withValues(alpha: 0.4)),
                    ),
                    child: Text(item, style: const TextStyle(fontSize: 11, color: Color(0xFF58A6FF))),
                  );
                }),
                GestureDetector(
                  onTap: () => _showMultiSelectPicker(habit),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Text(
                      (_currentEntry.multiSelects[habit.id] ?? []).isEmpty ? '+ Select options...' : '+ Edit selection',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (habit.type == HabitPropertyType.text) ...[
            const SizedBox(height: 6),
            TextFormField(
              initialValue: _currentEntry.textValues[habit.id] ?? '',
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
        ],
      ),
    );
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
                  if (habit.options.isEmpty)
                    const Text('No options defined. Edit habit to add comma-separated options.', style: TextStyle(fontSize: 12, color: Colors.grey))
                  else
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
            ..._activeHabits.map((h) => DataColumn(
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
            final habitsForDate = HabitHiveRepository.instance.getActiveHabitsForDate(entry);
            final d = DateTime.parse(dateKey);
            final formatted = _formatNotionDateHeader(d);
            final score = HabitHiveRepository.instance.calculateDailyScore(habitsForDate, entry);

            return DataRow(
              cells: [
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
                ..._activeHabits.map((habit) {
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