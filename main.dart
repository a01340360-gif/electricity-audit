import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'فحص الكهرباء',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E20)),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: Directionality.of(context),
          child: child ?? const SizedBox(),
        );
      },
      home: const HomeScreen(),
    );
  }
}

// ================== النماذج (Models) ==================
class User {
  final int? id;
  final String name;
  User({this.id, required this.name});
  Map<String, dynamic> toMap() => {'id': id, 'name': name};
  factory User.fromMap(Map<String, dynamic> m) => User(id: m['id'], name: m['name']);
}

class Street {
  final int? id;
  final int userId;
  final String name;
  final String? centralMeter;
  final double centralPrev;
  
  Street({this.id, required this.userId, required this.name, this.centralMeter, this.centralPrev = 0});
  
  Map<String, dynamic> toMap() => {
    'id': id, 'user_id': userId, 'name': name, 'central_meter': centralMeter, 'central_prev': centralPrev
  };
  
  factory Street.fromMap(Map<String, dynamic> m) => Street(
    id: m['id'], userId: m['user_id'] ?? 1, name: m['name'], centralMeter: m['central_meter'],
    centralPrev: (m['central_prev'] as num?)?.toDouble() ?? 0.0
  );
}

class Meter {
  final int? id;
  final int streetId;
  final String meterNo;
  final String? subscriber;
  final double prevReading;
  final String status;
  
  Meter({this.id, required this.streetId, required this.meterNo, this.subscriber, this.prevReading = 0, this.status = 'سليم'});
  
  Map<String, dynamic> toMap() => {
    'id': id, 'street_id': streetId, 'meter_no': meterNo, 'subscriber': subscriber, 'prev_reading': prevReading, 'status': status
  };
  
  factory Meter.fromMap(Map<String, dynamic> m) => Meter(
    id: m['id'], streetId: m['street_id'], meterNo: m['meter_no'], subscriber: m['subscriber'],
    prevReading: (m['prev_reading'] as num?)?.toDouble() ?? 0.0, status: m['status'] ?? 'سليم'
  );
}

class Inspection {
  final int? id;
  final int streetId;
  final String periodType;
  final String start;
  final String end;
  final double central;
  final double subTotal;
  final double shared;
  final double lighting;
  final double loss;
  final double lossPercent;
  
  Inspection({this.id, required this.streetId, required this.periodType, required this.start, required this.end, required this.central, required this.subTotal, required this.shared, required this.lighting, required this.loss, required this.lossPercent});
  
  Map<String, dynamic> toMap() => {
    'id': id, 'street_id': streetId, 'period_type': periodType, 'start': start, 'end': end,
    'central': central, 'sub_total': subTotal, 'shared': shared, 'lighting': lighting,
    'loss': loss, 'loss_percent': lossPercent
  };
  
  factory Inspection.fromMap(Map<String, dynamic> m) => Inspection(
    id: m['id'], streetId: m['street_id'], periodType: m['period_type'], start: m['start'], end: m['end'],
    central: (m['central'] as num).toDouble(), subTotal: (m['sub_total'] as num).toDouble(), 
    shared: (m['shared'] as num).toDouble(), lighting: (m['lighting'] as num).toDouble(),
    loss: (m['loss'] as num).toDouble(), lossPercent: (m['loss_percent'] as num).toDouble()
  );
}

// ================== قاعدة البيانات (DBHelper) ==================
class DBHelper {
  static final DBHelper instance = DBHelper._();
  DBHelper._();
  static Database? _db;

  Future<Database> get db async {
    _db ??= await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = '${await getDatabasesPath()}/elec.db';
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
        await db.execute('CREATE TABLE streets(id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER DEFAULT 1, name TEXT, central_meter TEXT, central_prev REAL DEFAULT 0)');
        await db.execute('CREATE TABLE meters(id INTEGER PRIMARY KEY AUTOINCREMENT, street_id INTEGER, meter_no TEXT, subscriber TEXT, prev_reading REAL DEFAULT 0, status TEXT DEFAULT "سليم")');
        await db.execute('CREATE TABLE inspections(id INTEGER PRIMARY KEY AUTOINCREMENT, street_id INTEGER, period_type TEXT, start TEXT, end TEXT, central REAL, sub_total REAL, shared REAL, lighting REAL, loss REAL, loss_percent REAL)');
        await db.execute('CREATE TABLE readings(id INTEGER PRIMARY KEY AUTOINCREMENT, inspection_id INTEGER, meter_id INTEGER, reading REAL)');
        await db.insert('users', {'name': 'المدير'});
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          try { await db.execute('CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)'); } catch(_){}
          try { await db.insert('users', {'name': 'المدير'}); } catch(_){}
          try { await db.execute('ALTER TABLE streets ADD COLUMN user_id INTEGER DEFAULT 1'); } catch(_){}
        }
        if (oldV < 3) {
          try { await db.execute('ALTER TABLE streets ADD COLUMN central_prev REAL DEFAULT 0'); } catch(_){}
          try { await db.execute('ALTER TABLE meters ADD COLUMN prev_reading REAL DEFAULT 0'); } catch(_){}
        }
        if (oldV < 4) {
          await db.execute('UPDATE streets SET user_id = 1 WHERE user_id IS NULL');
        }
        if (oldV < 5) {
          try { await db.execute('ALTER TABLE meters ADD COLUMN status TEXT DEFAULT "سليم"'); } catch(_){}
        }
      }
    );
  }

  Future<List<User>> getUsers() async {
    final d = await db;
    final res = await d.query('users');
    if (res.isEmpty) {
      await d.insert('users', {'name': 'المدير'});
      return [User(id: 1, name: 'المدير')];
    }
    return res.map(User.fromMap).toList();
  }

  Future<int> addUser(String name) async {
    final d = await db;
    return d.insert('users', {'name': name});
  }

  Future<List<Street>> getAllStreets() async {
    final d = await db;
    final res = await d.query('streets');
    return res.map(Street.fromMap).toList();
  }

  Future<int> addStreet(int userId, String name, String central, double centralPrev) async {
    final d = await db;
    return d.insert('streets', {'user_id': userId, 'name': name, 'central_meter': central, 'central_prev': centralPrev});
  }

  Future<int> updateStreet(Street s) async {
    final d = await db;
    return d.update('streets', s.toMap(), where: 'id = ?', whereArgs: [s.id]);
  }

  Future<int> deleteStreet(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.rawDelete('DELETE FROM readings WHERE meter_id IN (SELECT id FROM meters WHERE street_id = ?)', [id]);
      await txn.rawDelete('DELETE FROM readings WHERE inspection_id IN (SELECT id FROM inspections WHERE street_id = ?)', [id]);
      await txn.delete('inspections', where: 'street_id = ?', whereArgs: [id]);
      await txn.delete('meters', where: 'street_id = ?', whereArgs: [id]);
      return txn.delete('streets', where: 'id = ?', whereArgs: [id]);
    });
    return 1;
  }

  Future<List<Meter>> getMeters(int streetId) async {
    final d = await db;
    final res = await d.query('meters', where: 'street_id = ?', whereArgs: [streetId], orderBy: 'CAST(meter_no AS INTEGER) ASC');
    return res.map(Meter.fromMap).toList();
  }

  Future<String> nextMeterNo(int streetId) async {
    final d = await db;
    final r = await d.rawQuery('SELECT MAX(CAST(meter_no AS INTEGER)) AS mx FROM meters WHERE street_id = ?', [streetId]);
    final mx = (r.first['mx'] as num?)?.toInt() ?? 0;
    return '${mx + 1}';
  }

  Future<int> addMeter(int streetId, String no, String sub, double prevReading, String status) async {
    final d = await db;
    return d.insert('meters', {'street_id': streetId, 'meter_no': no, 'subscriber': sub, 'prev_reading': prevReading, 'status': status});
  }

  Future<int> updateMeter(Meter m) async {
    final d = await db;
    return d.update('meters', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
  }

  Future<int> deleteMeter(int id) async {
    final d = await db;
    return d.delete('meters', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getPreviousReadingForMeter(int meterId, int? beforeInspectionId, int streetId) async {
    final d = await db;
    List<Map<String, dynamic>> res;
    if (beforeInspectionId != null) {
      res = await d.rawQuery('''
        SELECT r.reading FROM readings r
        INNER JOIN inspections i ON r.inspection_id = i.id
        WHERE r.meter_id = ? AND i.street_id = ? AND i.id < ?
        ORDER BY i.id DESC LIMIT 1
      ''', [meterId, streetId, beforeInspectionId]);
    } else {
      res = await d.rawQuery('''
        SELECT r.reading FROM readings r
        INNER JOIN inspections i ON r.inspection_id = i.id
        WHERE r.meter_id = ? AND i.street_id = ?
        ORDER BY i.id DESC LIMIT 1
      ''', [meterId, streetId]);
    }
    if (res.isNotEmpty) return (res.first['reading'] as num).toDouble();
    
    final m = await d.query('meters', where: 'id = ?', whereArgs: [meterId]);
    return (m.first['prev_reading'] as num?)?.toDouble() ?? 0;
  }

  Future<double> getPreviousCentral(int streetId, int? beforeInspectionId) async {
    final d = await db;
    List<Map<String, dynamic>> res;
    if (beforeInspectionId != null) {
      res = await d.query('inspections', where: 'street_id = ? AND id < ?', whereArgs: [streetId, beforeInspectionId], orderBy: 'id DESC', limit: 1);
    } else {
      res = await d.query('inspections', where: 'street_id = ?', whereArgs: [streetId], orderBy: 'id DESC', limit: 1);
    }
    if (res.isNotEmpty) return (res.first['central'] as num).toDouble();
    
    final s = await d.query('streets', where: 'id = ?', whereArgs: [streetId]);
    return (s.first['central_prev'] as num?)?.toDouble() ?? 0;
  }

  Future<Inspection?> getLastInspection(int streetId) async {
    final d = await db;
    final res = await d.query('inspections', where: 'street_id = ?', whereArgs: [streetId], orderBy: 'id DESC', limit: 1);
    if (res.isEmpty) return null;
    return Inspection.fromMap(res.first);
  }

  Future<List<Inspection>> getStreetInspections(int streetId) async {
    final d = await db;
    final res = await d.query('inspections', where: 'street_id = ?', whereArgs: [streetId], orderBy: 'id DESC');
    return res.map(Inspection.fromMap).toList();
  }

  Future<Map<int, double>> getInspectionReadings(int inspectionId) async {
    final d = await db;
    final res = await d.query('readings', where: 'inspection_id = ?', whereArgs: [inspectionId]);
    return {for (var r in res) (r['meter_id'] as int): (r['reading'] as num).toDouble()};
  }

  Future<int> deleteInspection(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('readings', where: 'inspection_id = ?', whereArgs: [id]);
      return txn.delete('inspections', where: 'id = ?', whereArgs: [id]);
    });
    return 1;
  }

  Future<void> saveInspection(Inspection ins, Map<int, double> readings, Map<int, String> statuses) async {
    final d = await db;
    await d.transaction((txn) async {
      final insId = await txn.insert('inspections', ins.toMap());
      for (var e in readings.entries) {
        await txn.insert('readings', {'inspection_id': insId, 'meter_id': e.key, 'reading': e.value});
      }
      for (var e in statuses.entries) {
        await txn.update('meters', {'status': e.value}, where: 'id = ?', whereArgs: [e.key]);
      }
    });
  }

  Future<void> updateInspection(int id, Inspection ins, Map<int, double> readings, Map<int, String> statuses) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.update('inspections', ins.toMap(), where: 'id = ?', whereArgs: [id]);
      await txn.delete('readings', where: 'inspection_id = ?', whereArgs: [id]);
      for (var e in readings.entries) {
        await txn.insert('readings', {'inspection_id': id, 'meter_id': e.key, 'reading': e.value});
      }
      for (var e in statuses.entries) {
        await txn.update('meters', {'status': e.value}, where: 'id = ?', whereArgs: [e.key]);
      }
    });
  }

  Future<List<Inspection>> getAllInspections() async {
    final d = await db;
    final res = await d.query('inspections', orderBy: 'id DESC');
    return res.map(Inspection.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getMeterReadings(int meterId) async {
    final d = await db;
    return d.rawQuery('''
      SELECT r.reading, i.end AS inspection_date, i.id AS inspection_id
      FROM readings r
      INNER JOIN inspections i ON r.inspection_id = i.id
      WHERE r.meter_id = ?
      ORDER BY i.id ASC
    ''', [meterId]);
  }

  Future<String> backupData() async {
    final d = await db;
    final users = await d.query('users');
    final streets = await d.query('streets');
    final meters = await d.query('meters');
    final inspections = await d.query('inspections');
    final readings = await d.query('readings');
    return jsonEncode({
      'users': users, 'streets': streets, 'meters': meters, 'inspections': inspections, 'readings': readings,
    });
  }

  Future<void> restoreData(String jsonString) async {
    final data = jsonDecode(jsonString);
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('readings');
      await txn.delete('inspections');
      await txn.delete('meters');
      await txn.delete('streets');
      await txn.delete('users');

      for (var row in data['users'] ?? []) { await txn.insert('users', Map<String, dynamic>.from(row)); }
      for (var row in data['streets']) { await txn.insert('streets', Map<String, dynamic>.from(row)); }
      for (var row in data['meters']) { await txn.insert('meters', Map<String, dynamic>.from(row)); }
      for (var row in data['inspections']) { await txn.insert('inspections', Map<String, dynamic>.from(row)); }
      for (var row in data['readings']) { await txn.insert('readings', Map<String, dynamic>.from(row)); }
      
      for (final t in ['users', 'streets', 'meters', 'inspections', 'readings']) {
        final maxId = Sqflite.firstIntValue(await txn.rawQuery('SELECT MAX(id) FROM $t')) ?? 0;
        await txn.rawDelete('DELETE FROM sqlite_sequence WHERE name = ?', [t]);
        if (maxId > 0) {
          await txn.rawInsert('INSERT INTO sqlite_sequence(name, seq) VALUES(?, ?)', [t, maxId]);
        }
      }
    });
  }
}

// ================== دوال مساعدة (Utils) ==================
class Utils {
  static final fmt = NumberFormat('#,##0.##', 'en');
  static String n(num v) => fmt.format(v);
  
  static const double nameFontSize = 16;
  static const double subFontSize = 13;
  
  static Color riskColor(double p) {
    if (p < 0) return Colors.grey;
    if (p >= 100) return const Color(0xFFB71C1C);
    if (p > 35) return Colors.red;                
    if (p > 20) return Colors.orange;             
    if (p > 10) return Colors.amber;              
    return Colors.green;                          
  }
  
  static String riskName(double p) {
    if (p < 0) return 'قراءات غير منطقية (سالب)';
    if (p >= 100) return 'خطر شديد جداً (تلاعب)';
    if (p > 35) return 'خطر (سرقة محتملة)';
    if (p > 20) return 'مشكوك';
    if (p > 10) return 'تحذير';
    return 'طبيعي';
  }

  static Color getStatusColor(String status) {
    switch (status) {
      case 'طافي': return Colors.grey;
      case 'واقف': return Colors.orange;
      case 'خلل': return Colors.red;
      case 'مشكوك': return Colors.purple;
      default: return Colors.green;
    }
  }
}

class EnglishNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text;
    text = text.split('').map((c) {
      final code = c.codeUnitAt(0);
      if (code >= 0x0660 && code <= 0x0669) return String.fromCharCode(code - 0x0660 + 0x30);
      if (code >= 0x06F0 && code <= 0x06F9) return String.fromCharCode(code - 0x06F0 + 0x30);
      return c;
    }).join();
    text = text.replaceAll(',', '');

    if (RegExp(r'^-?\d*\.?\d*$').hasMatch(text)) {
      return TextEditingValue(text: text, selection: newValue.selection);
    }
    return oldValue;
  }
}

// ================== الشاشات ==================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Street> streets = [];
  List<Inspection> ins = [];
  List<User> users = [];
  User? currentUser;
  
  @override
  void initState() {
    super.initState();
    _loadInitial();
  }
  
  void _loadInitial() async {
    users = await DBHelper.instance.getUsers();
    currentUser = users.first;
    await _loadData();
  }

  Future<void> _loadData() async {
    if (currentUser == null) return;
    streets = await DBHelper.instance.getAllStreets();
    ins = await DBHelper.instance.getAllInspections();
    setState(() {});
  }

  void _switchUser(User user) {
    setState(() { currentUser = user; });
    _loadData();
  }

  void _addUserDialog() {
    final name = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مستخدم جديد'),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (name.text.isNotEmpty) {
                await DBHelper.instance.addUser(name.text);
                users = await DBHelper.instance.getUsers();
                setState(() {});
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // دالة عرض نافذة التعليمات
  void _showInstructionsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.support_agent, color: Colors.blue, size: 30),
            SizedBox(width: 8),
            Text('Assistance', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('تعليمات الاستخدام', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16)),
                const Divider(color: Colors.blue),
                const SizedBox(height: 8),
                _buildInstructionStep('1', 'أضف الشوارع والعدادات من زر "إدارة الشوارع والعدادات".'),
                _buildInstructionStep('2', 'اضغط على أي شارع لبدء عملية "فحص جديد".'),
                _buildInstructionStep('3', 'أدخل القراءات الحالية لكل عداد، وسيقوم النظام بحساب الفاقد تلقائياً.'),
                _buildInstructionStep('4', 'يمكنك تغيير حالة العداد (سليم، طافي، خلل...) من القائمة المنسدلة بجانب كل عداد.'),
                _buildInstructionStep('5', 'لعرض النتائج السابقة أو تعديلها، اضغط على أيقونة الساعة (سجل الفحوصات) أعلى شاشة العدادات.'),
                _buildInstructionStep('6', 'احفظ نسخة احتياطية من الشاشة الرئيسية قبل عمل أي تحديثات.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إخفاء', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(number, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }

  void _backup() async {
    try {
      final jsonStr = await DBHelper.instance.backupData();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/elec_backup.json');
      await file.writeAsString(jsonStr);
      await Share.shareXFiles([XFile(file.path)], text: 'نسخة احتياطية لتطبيق فحص الكهرباء');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  void _restore() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        final jsonStr = utf8.decode(bytes, allowMalformed: true);
        
        await DBHelper.instance.restoreData(jsonStr);
        _loadInitial();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم استيراد البيانات بنجاح!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستيراد: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('فحص الكهرباء'), 
        backgroundColor: Colors.green.shade100,
        actions: [
          // زر التعليمات الجديد
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.blue),
            tooltip: 'تعليمات الاستخدام',
            onPressed: _showInstructionsDialog,
          ),
          PopupMenuButton<User>(
            icon: const Icon(Icons.person),
            tooltip: 'تبديل المستخدم',
            onSelected: _switchUser,
            itemBuilder: (context) => users.map((u) => PopupMenuItem(value: u, child: Text(u.name))).toList(),
          ),
          IconButton(icon: const Icon(Icons.add_moderator), onPressed: _addUserDialog),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.green.shade50,
            child: ListTile(
              leading: const Icon(Icons.electric_meter, size: 40),
              title: const Text('نظام مراجعة وحساب الفاقد', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('مرحباً: ${currentUser!.name}'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _statCard('الشوارع', '${streets.length}', Icons.streetview)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('الفحوصات', '${ins.length}', Icons.fact_check)),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => StreetsScreen(userId: currentUser!.id!)));
              _loadData();
            },
            icon: const Icon(Icons.streetview),
            label: const Text('إدارة الشوارع والعدادات'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: Colors.teal),
            onPressed: () async {
              if (streets.isEmpty) return;
              final s = await showDialog<Street>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('اختر الشارع للمتابعة'),
                  children: streets.map((st) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, st),
                    child: Text(st.name, style: const TextStyle(fontSize: 16)),
                  )).toList(),
                ),
              );
              if (s != null && mounted) {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => StreetDashboardScreen(street: s)));
                _loadData();
              }
            },
            icon: const Icon(Icons.dashboard, color: Colors.white),
            label: const Text('لوحة المتابعة الحية', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: Colors.grey.shade200, foregroundColor: Colors.black),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
              _loadData();
            },
            icon: const Icon(Icons.assessment),
            label: const Text('التقارير والنتائج النهائية'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const Text('النسخ الاحتياطي (هام جداً قبل التحديث):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _backup,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('تصدير نسخة'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _restore,
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('استيراد نسخة'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          const Center(
            child: Text(
              'تم عمل وصناعة هذا البرنامج بواسطة :\nعبدالله الزبيري\n777704402\nمحطة العاصمة باور',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _statCard(String label, String val, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: Colors.green),
            const SizedBox(height: 8),
            Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class StreetsScreen extends StatefulWidget {
  final int userId;
  const StreetsScreen({super.key, required this.userId});
  @override
  State<StreetsScreen> createState() => _StreetsScreenState();
}

class _StreetsScreenState extends State<StreetsScreen> {
  List<Street> list = [];
  List<Street> filtered = [];
  final searchCtrl = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _load();
  }
  
  void _load() async {
    list = await DBHelper.instance.getAllStreets();
    filtered = list;
    setState(() {});
  }

  void _search(String query) {
    setState(() {
      filtered = list.where((s) => s.name.contains(query) || (s.centralMeter ?? '').contains(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الشوارع')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(labelText: 'بحث عن شارع...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: filtered.isEmpty 
              ? const Center(child: Text('لا توجد شوارع مطابقة أو مضافة.'))
              : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final s = filtered[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.signpost),
                    title: Text(s.name, style: const TextStyle(fontSize: Utils.nameFontSize, fontWeight: FontWeight.bold)),
                    subtitle: Text('مركزي: ${s.centralMeter ?? "—"} | سابقة: ${Utils.n(s.centralPrev)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _addDialog(context, existing: s),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteDialog(context, s),
                        ),
                        const Icon(Icons.chevron_left),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => MetersScreen(street: s)));
                      _load();
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _deleteDialog(BuildContext parentContext, Street s) {
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الشارع "${s.name}"؟ سيتم حذف جميع عداداته وفحوصاته أيضاً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DBHelper.instance.deleteStreet(s.id!);
              if (parentContext.mounted) Navigator.pop(ctx);
              _load();
            },
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      )
    );
  }

  void _addDialog(BuildContext parentContext, {Street? existing}) {
    final name = TextEditingController(text: existing?.name ?? '');
    final cen = TextEditingController(text: existing?.centralMeter ?? '');
    final cenPrev = TextEditingController(text: existing != null ? existing.centralPrev.toString() : '0');
    
    showDialog(
      context: parentContext, 
      builder: (BuildContext ctx) => AlertDialog(
      title: Text(existing == null ? 'إضافة شارع' : 'تعديل شارع'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الشارع')),
            TextField(controller: cen, decoration: const InputDecoration(labelText: 'رقم العداد المركزي')),
            TextField(controller: cenPrev, keyboardType: TextInputType.number, inputFormatters: [EnglishNumberFormatter()], decoration: const InputDecoration(labelText: 'القراءة المركزية السابقة')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () async {
            if (name.text.isNotEmpty) {
              final cPrev = double.tryParse(cenPrev.text) ?? 0;
              if (existing == null) {
                await DBHelper.instance.addStreet(widget.userId, name.text, cen.text, cPrev);
              } else {
                await DBHelper.instance.updateStreet(Street(id: existing.id, userId: widget.userId, name: name.text, centralMeter: cen.text, centralPrev: cPrev));
              }
              if (parentContext.mounted) Navigator.pop(ctx);
              _load();
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    ));
  }
}

class MetersScreen extends StatefulWidget {
  final Street street;
  const MetersScreen({super.key, required this.street});
  @override
  State<MetersScreen> createState() => _MetersScreenState();
}

class _MetersScreenState extends State<MetersScreen> {
  List<Meter> meters = [];
  List<Meter> filtered = [];
  final searchCtrl = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _load();
  }
  
  void _load() async {
    meters = await DBHelper.instance.getMeters(widget.street.id!);
    filtered = meters;
    setState(() {});
  }

  void _search(String query) {
    setState(() {
      filtered = meters.where((m) => m.meterNo.contains(query) || (m.subscriber ?? '').contains(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.street.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'سجل الفحوصات',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => StreetHistoryScreen(street: widget.street)));
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(labelText: 'بحث عن مشترك أو عداد...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: filtered.isEmpty 
                ? const Center(child: Text('أضف عدادات للبدء أو لا توجد نتائج بحث'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final m = filtered[i];
                      final statusColor = Utils.getStatusColor(m.status);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.2),
                          child: Icon(Icons.speed, color: statusColor),
                        ),
                        title: Row(
                          children: [
                            Text('عداد ${m.meterNo}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: Utils.nameFontSize)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4)),
                              child: Text(m.status, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.subscriber ?? '—', style: TextStyle(fontSize: Utils.subFontSize, fontWeight: FontWeight.w600, color: Colors.black87)),
                            Text('السابقة: ${Utils.n(m.prevReading)}', style: const TextStyle(fontSize: 11, color: Colors.blue)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _addDialog(context, existing: m),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteDialog(context, m),
                            ),
                          ],
                        ),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MeterHistoryScreen(meter: m, streetId: widget.street.id!))),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: '1',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => NewInspectionScreen(street: widget.street, meters: meters)));
              _load();
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('بدء فحص'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: '2',
            onPressed: () => _addDialog(context),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  void _deleteDialog(BuildContext parentContext, Meter m) {
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف العداد رقم "${m.meterNo}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DBHelper.instance.deleteMeter(m.id!);
              if (parentContext.mounted) Navigator.pop(ctx);
              _load();
            },
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      )
    );
  }

  Future<void> _addDialog(BuildContext parentContext, {Meter? existing}) async {
    String autoNo = existing?.meterNo ?? await DBHelper.instance.nextMeterNo(widget.street.id!);
    final sub = TextEditingController(text: existing?.subscriber ?? '');
    final prev = TextEditingController(text: existing != null ? existing.prevReading.toString() : '0');
    String selectedStatus = existing?.status ?? 'سليم';
    
    if (!parentContext.mounted) return;
    showDialog(
      context: parentContext, 
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(existing == null ? 'إضافة عداد' : 'تعديل عداد'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: TextEditingController(text: autoNo),
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'رقم العداد (تلقائي)', filled: true, fillColor: Color(0xFFF0F0F0)),
                  ),
                  TextField(controller: sub, decoration: const InputDecoration(labelText: 'اسم المشترك')),
                  TextField(controller: prev, keyboardType: TextInputType.number, inputFormatters: [EnglishNumberFormatter()], decoration: const InputDecoration(labelText: 'القراءة السابقة للعداد')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(labelText: 'حالة العداد', border: OutlineInputBorder()),
                    items: ['سليم', 'طافي', 'واقف', 'خلل', 'مشكوك'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (val) => setStateDialog(() => selectedStatus = val!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  final pRead = double.tryParse(prev.text) ?? 0;
                  if (existing == null) {
                    await DBHelper.instance.addMeter(widget.street.id!, autoNo, sub.text, pRead, selectedStatus);
                  } else {
                    await DBHelper.instance.updateMeter(Meter(id: existing.id, streetId: widget.street.id!, meterNo: autoNo, subscriber: sub.text, prevReading: pRead, status: selectedStatus));
                  }
                  if (parentContext.mounted) Navigator.pop(ctx);
                  _load();
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        }
      ),
    );
  }
}

class StreetHistoryScreen extends StatefulWidget {
  final Street street;
  const StreetHistoryScreen({super.key, required this.street});
  @override
  State<StreetHistoryScreen> createState() => _StreetHistoryScreenState();
}

class _StreetHistoryScreenState extends State<StreetHistoryScreen> {
  List<Inspection> list = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    list = await DBHelper.instance.getStreetInspections(widget.street.id!);
    setState(() => loading = false);
  }

  void _deleteInspection(BuildContext ctx, Inspection ins) async {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('حذف فحص'),
        content: const Text('هل أنت متأكد من حذف هذا الفحص؟ لن يتم التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DBHelper.instance.deleteInspection(ins.id!);
              if (c.mounted) Navigator.pop(c);
              _load();
            },
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('سجل فحوصات ${widget.street.name}')),
      body: loading ? const Center(child: CircularProgressIndicator()) :
             list.isEmpty ? const Center(child: Text('لا توجد فحوصات سابقة')) :
             ListView.builder(
               itemCount: list.length,
               itemBuilder: (context, i) {
                 final ins = list[i];
                 final color = Utils.riskColor(ins.lossPercent);
                 return Card(
                   margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                   child: ListTile(
                     title: Text('التاريخ: ${ins.end}', style: const TextStyle(fontWeight: FontWeight.bold)),
                     subtitle: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text('المركزي: ${Utils.n(ins.central)}'),
                         Text('الفوارق: ${Utils.n(ins.subTotal)}'),
                         Text('الفاقد: ${Utils.n(ins.loss)} (${ins.lossPercent.toStringAsFixed(1)}%)', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                       ],
                     ),
                     trailing: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         IconButton(
                           icon: const Icon(Icons.edit, color: Colors.blue),
                           tooltip: 'تعديل',
                           onPressed: () async {
                             final meters = await DBHelper.instance.getMeters(widget.street.id!);
                             if (!mounted) return;
                             await Navigator.push(context, MaterialPageRoute(
                               builder: (_) => NewInspectionScreen(street: widget.street, meters: meters, existingInspection: ins),
                             ));
                             _load();
                           },
                         ),
                         IconButton(
                           icon: const Icon(Icons.delete, color: Colors.red),
                           onPressed: () => _deleteInspection(context, ins),
                         ),
                       ],
                     ),
                   ),
                 );
               },
             ),
    );
  }
}

class NewInspectionScreen extends StatefulWidget {
  final Street street;
  final List<Meter> meters;
  final Inspection? existingInspection;
  const NewInspectionScreen({super.key, required this.street, required this.meters, this.existingInspection});
  @override
  State<NewInspectionScreen> createState() => _NewInspectionScreenState();
}

class _NewInspectionScreenState extends State<NewInspectionScreen> {
  final central = TextEditingController(text: '0');
  final shared = TextEditingController(text: '0');
  final lighting = TextEditingController(text: '0');
  
  Map<int, TextEditingController> currentReads = {};
  Map<int, double> previousReads = {};
  Map<int, String> currentStatuses = {};
  Map<int, double> previousPeriodConsumption = {};
  List<FocusNode> _focusNodes = [];
  
  double prevCentral = 0;
  bool isLoading = true;
  DateTime selectedDate = DateTime.now();

  bool get isEditing => widget.existingInspection != null;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  @override
  void dispose() {
    for (var node in _focusNodes) { node.dispose(); }
    for (var c in currentReads.values) { c.dispose(); }
    super.dispose();
  }

  void _preload() async {
    final editing = widget.existingInspection;
    
    prevCentral = await DBHelper.instance.getPreviousCentral(widget.street.id!, editing?.id);

    Map<int, double>? existingReadings;
    if (editing != null) {
      existingReadings = await DBHelper.instance.getInspectionReadings(editing.id!);
      central.text = editing.central % 1 == 0 ? editing.central.toInt().toString() : editing.central.toString();
      shared.text = editing.shared % 1 == 0 ? editing.shared.toInt().toString() : editing.shared.toString();
      lighting.text = editing.lighting % 1 == 0 ? editing.lighting.toInt().toString() : editing.lighting.toString();
      try { selectedDate = DateFormat('yyyy-MM-dd').parse(editing.end); } catch (_) {}
    }

    for (var m in widget.meters) {
      final prev = await DBHelper.instance.getPreviousReadingForMeter(m.id!, editing?.id, widget.street.id!);
      previousReads[m.id!] = prev;
      // احسب استهلاك الفترة السابقة من آخر قراءتين محفوظتين لهذا العداد.
      final history = await DBHelper.instance.getMeterReadings(m.id!);
      if (history.length >= 2) {
        final last = (history[history.length - 1]['reading'] as num).toDouble();
        final beforeLast = (history[history.length - 2]['reading'] as num).toDouble();
        previousPeriodConsumption[m.id!] = last - beforeLast;
      }
      currentStatuses[m.id!] = m.status;
      
      final initVal = existingReadings?[m.id!] ?? prev;
      String initStr = initVal % 1 == 0 ? initVal.toInt().toString() : initVal.toString();
      
      currentReads[m.id!] = TextEditingController(text: initStr);
      _focusNodes.add(FocusNode());
    }
    setState(() => isLoading = false);
  }

  double get currentCentral => double.tryParse(central.text) ?? 0;
  double get sharedVal => double.tryParse(shared.text) ?? 0;
  double get lightingVal => double.tryParse(lighting.text) ?? 0;
  double get centralDiff => currentCentral - prevCentral;
  double get totalPrevReadings => previousReads.values.fold(0.0, (sum, val) => sum + val);
  
  double get totalCurrentReadings {
    double total = 0;
    for (var m in widget.meters) {
      total += (double.tryParse(currentReads[m.id!]?.text ?? '0') ?? 0);
    }
    return total;
  }

  double get totalSubDiffs => totalCurrentReadings - totalPrevReadings;
  double get loss => centralDiff - (totalSubDiffs + sharedVal + lightingVal);
  double get lossPct => centralDiff > 0 ? (loss / centralDiff) * 100 : 0;

  String automaticStatus(int meterId, double consumption) {
    final baseline = previousPeriodConsumption[meterId];
    if (baseline == null || baseline <= 0 || consumption < 0) return consumption < 0 ? 'مشكوك' : 'سليم';
    final changePct = ((consumption - baseline).abs() / baseline) * 100;
    return changePct > 30 ? 'مشكوك' : 'سليم';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    final color = Utils.riskColor(lossPct);
    final dateStr = DateFormat('yyyy-MM-dd', 'en').format(selectedDate);
    bool isCentralValid = currentCentral >= prevCentral;
    
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'تعديل فحص سابق' : 'فحص جديد (فوارق)')),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, left: 12, right: 12, bottom: 250), 
        children: [
          Card(
            color: Colors.amber.shade50,
            child: ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.orange),
              title: const Text('تاريخ الفحص:', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(dateStr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange)),
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('القراءة المركزية السابقة:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  Text(Utils.n(prevCentral), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: central, 
                    keyboardType: TextInputType.number, 
                    inputFormatters: [EnglishNumberFormatter()],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'القراءة المركزية الحالية (الكلي)', 
                      border: const OutlineInputBorder(),
                      errorText: !isCentralValid ? 'القراءة الحالية أقل من السابقة!' : null,
                    ), 
                    onChanged: (_) => setState((){})
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: shared, 
                          keyboardType: TextInputType.number, 
                          inputFormatters: [EnglishNumberFormatter()],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'أحمال مشتركة (للفترة)'), 
                          onChanged: (_) => setState((){}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: lighting, 
                          keyboardType: TextInputType.number, 
                          inputFormatters: [EnglishNumberFormatter()],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'إنارة (للفترة)'), 
                          onChanged: (_) => setState((){}),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('القراءات الحالية للعدادات:', style: TextStyle(fontWeight: FontWeight.bold)),
          ...List.generate(widget.meters.length, (index) {
            final m = widget.meters[index];
            final prev = previousReads[m.id!] ?? 0;
            final currentStr = currentReads[m.id!]?.text ?? '0';
            final currentVal = double.tryParse(currentStr) ?? 0;
            bool isSubValid = currentVal >= prev;
            final consumption = currentVal - prev;
            Color consColor = consumption < 0 ? Colors.red : (consumption == 0 ? Colors.orange : Colors.green);
            
            final currentStatus = automaticStatus(m.id!, consumption);
            currentStatuses[m.id!] = currentStatus;
            final baseline = previousPeriodConsumption[m.id!];
            final statusColor = Utils.getStatusColor(currentStatus);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              shape: RoundedRectangleBorder(
                side: BorderSide(color: statusColor.withOpacity(0.5), width: 1),
                borderRadius: BorderRadius.circular(12)
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('عداد ${m.meterNo}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: Utils.nameFontSize)),
                              const SizedBox(width: 6),
                              Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: statusColor),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 7),
                                  child: Center(
                                    child: Text(currentStatus, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(m.subscriber ?? '—', style: TextStyle(fontSize: Utils.subFontSize, fontWeight: FontWeight.w600, color: Colors.black87)),
                          Text('السابقة: ${Utils.n(prev)}', style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold)),
                          Text('استهلاك الفترة السابقة: ${baseline == null ? 'لا توجد مقارنة كافية' : Utils.n(baseline)}', style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                          if (consumption != 0)
                            Text('الاستهلاك: ${Utils.n(consumption)}', style: TextStyle(fontSize: 11, color: consColor, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: currentReads[m.id!],
                        focusNode: _focusNodes[index],
                        onTap: () {
                          final c = currentReads[m.id!]!;
                          c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
                        },
                        keyboardType: TextInputType.number,
                        inputFormatters: [EnglishNumberFormatter()],
                        textInputAction: index == widget.meters.length - 1 ? TextInputAction.done : TextInputAction.next,
                        onSubmitted: (_) {
                          if (index < widget.meters.length - 1) {
                            FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
                          } else {
                            FocusScope.of(context).unfocus();
                          }
                        },
                        decoration: InputDecoration(
                          isDense: true, 
                          border: const OutlineInputBorder(), 
                          labelText: 'الحالية',
                          errorText: !isSubValid ? 'أقل من السابقة' : null,
                        ),
                        onChanged: (_) => setState((){}),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(top: 12, left: 12, right: 12, bottom: 60), 
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
          border: Border(top: BorderSide(color: color, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('المركزي (الحالي - السابق):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13)),
                Text('${Utils.n(currentCentral)} - ${Utils.n(prevCentral)} = ${Utils.n(centralDiff)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الفرعية (الحالي - السابق):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13)),
                Text('${Utils.n(totalCurrentReadings)} - ${Utils.n(totalPrevReadings)} = ${Utils.n(totalSubDiffs)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 14)),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الفاقد التقديري:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('${Utils.n(loss)} (${lossPct.toStringAsFixed(1)}%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
              ],
            ),
            if (lossPct > 10) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تحذير: نسبة الفاقد مرتفعة جداً (${lossPct.toStringAsFixed(1)}%)!',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(45), 
                backgroundColor: color
              ),
              onPressed: () async {
                final ins = Inspection(
                  streetId: widget.street.id!, periodType: 'custom', start: dateStr, end: dateStr,
                  central: currentCentral, subTotal: totalSubDiffs, shared: sharedVal, lighting: lightingVal, loss: loss, lossPercent: lossPct,
                );
                final rMap = {for (var e in currentReads.entries) e.key: double.tryParse(e.value.text) ?? 0};
                
                if (isEditing) {
                  await DBHelper.instance.updateInspection(widget.existingInspection!.id!, ins, rMap, currentStatuses);
                } else {
                  await DBHelper.instance.saveInspection(ins, rMap, currentStatuses);
                }
                
                if (mounted) Navigator.pop(context);
              },
              child: Text(isEditing ? 'حفظ التعديلات' : 'حفظ الفحص', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

class MeterHistoryScreen extends StatefulWidget {
  final Meter meter;
  final int streetId;
  const MeterHistoryScreen({super.key, required this.meter, required this.streetId});
  @override
  State<MeterHistoryScreen> createState() => _MeterHistoryScreenState();
}

class _MeterHistoryScreenState extends State<MeterHistoryScreen> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    rows = await DBHelper.instance.getMeterReadings(widget.meter.id!);
    setState(() => loading = false);
  }

  double get avgConsumption {
    if (rows.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < rows.length; i++) {
      total += (rows[i]['reading'] as num).toDouble() - (rows[i - 1]['reading'] as num).toDouble();
    }
    return total / (rows.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = Utils.getStatusColor(widget.meter.status);
    return Scaffold(
      appBar: AppBar(title: Text('عداد ${widget.meter.meterNo}')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  color: Colors.green.shade50,
                  child: ListTile(
                    title: Row(
                      children: [
                        Text(widget.meter.subscriber ?? '—', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(widget.meter.status, style: const TextStyle(color: Colors.white, fontSize: 10)),
                          backgroundColor: statusColor,
                        ),
                      ],
                    ),
                    subtitle: Text('السابقة الأولية: ${Utils.n(widget.meter.prevReading)}'),
                  ),
                ),
                Card(
                  color: Colors.blue.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.show_chart, color: Colors.blue),
                    title: const Text('متوسط الاستهلاك', style: TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Text(Utils.n(avgConsumption), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
                ),
                const SizedBox(height: 8),
                if (rows.isEmpty) const Center(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('لا توجد قراءات مسجلة بعد'),
                )),
                ...List.generate(rows.length, (i) {
                  final r = rows[i];
                  final current = (r['reading'] as num).toDouble();
                  final prev = i > 0 ? (rows[i - 1]['reading'] as num).toDouble() : widget.meter.prevReading;
                  final cons = current - prev;
                  Color color = Colors.green;
                  String note = 'طبيعي';
                  if (cons < 0) { color = Colors.red; note = 'قراءة سالبة ⚠'; }
                  else if (cons == 0) { color = Colors.orange; note = 'استهلاك صفر ⚠'; }
                  else if (avgConsumption > 0 && cons > avgConsumption * 3) { color = Colors.deepOrange; note = 'مرتفع جدًا 🔥'; }
                  else if (avgConsumption > 0 && cons < avgConsumption * 0.2) { color = Colors.amber; note = 'منخفض مشبوه'; }
                  
                  return Card(
                    child: ListTile(
                      dense: true,
                      title: Text('${r['inspection_date']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${Utils.n(prev)} → ${Utils.n(current)}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(Utils.n(cons), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
                          Text(note, style: TextStyle(fontSize: 10, color: color)),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class StreetDashboardScreen extends StatefulWidget {
  final Street street;
  const StreetDashboardScreen({super.key, required this.street});
  @override
  State<StreetDashboardScreen> createState() => _StreetDashboardScreenState();
}

class _StreetDashboardScreenState extends State<StreetDashboardScreen> {
  Map<String, dynamic>? snapshot;
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final ins = await DBHelper.instance.getLastInspection(widget.street.id!);
    if (ins == null) {
      setState(() { snapshot = null; loading = false; });
      return;
    }
    
    final meters = await DBHelper.instance.getMeters(widget.street.id!);
    final currentReads = await DBHelper.instance.getInspectionReadings(ins.id!);
    
    List<Map<String, dynamic>> meterData = [];
    for (var m in meters) {
      final prev = await DBHelper.instance.getPreviousReadingForMeter(m.id!, ins.id, widget.street.id!);
      final current = currentReads[m.id!];
      meterData.add({
        'id': m.id, 'meter_no': m.meterNo, 'subscriber': m.subscriber,
        'prev': prev, 'current': current,
        'consumption': current != null ? current - prev : null,
        'status': m.status,
      });
    }
    
    setState(() {
      snapshot = {'inspection': ins, 'meters': meterData};
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (snapshot == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.street.name)),
        body: const Center(child: Text('لا توجد فحوصات بعد لهذا الشارع')),
      );
    }
    final ins = snapshot!['inspection'] as Inspection;
    final meters = (snapshot!['meters'] as List).cast<Map<String, dynamic>>();
    final color = Utils.riskColor(ins.lossPercent);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.street.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () { setState(() => loading = true); _load(); },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: color.withOpacity(0.15),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('آخر فحص:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(ins.end, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('المركزي:'),
                    Text(Utils.n(ins.central), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('مجموع الاستهلاك:'),
                    Text(Utils.n(ins.subTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('الفاقد:'),
                    Text('${Utils.n(ins.loss)} (${ins.lossPercent.toStringAsFixed(1)}%)', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
                  ]),
                  const SizedBox(height: 4),
                  Chip(
                    label: Text(Utils.riskName(ins.lossPercent), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    backgroundColor: color,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('استهلاك العدادات (${meters.length}):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ...meters.map((m) {
            final cons = m['consumption'] as double?;
            final statusColor = Utils.getStatusColor(m['status'] as String);
            Color c = Colors.grey;
            if (cons != null) {
              if (cons < 0) c = Colors.red;
              else if (cons == 0) c = Colors.orange;
              else c = Colors.green;
            }
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: statusColor.withOpacity(0.2),
                  child: Text(m['meter_no'].toString(), style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                title: Row(
                  children: [
                    Text(m['subscriber'] ?? '—', style: TextStyle(fontSize: Utils.subFontSize, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4)),
                      child: Text(m['status'], style: const TextStyle(color: Colors.white, fontSize: 9)),
                    ),
                  ],
                ),
                subtitle: Text('${Utils.n(m['prev'])} → ${m['current'] != null ? Utils.n(m['current']) : "لم يُقرأ"}', style: const TextStyle(fontSize: 11)),
                trailing: cons == null ? const Text('—') : Text(Utils.n(cons), style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 15)),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<Inspection> list = [];
  
  @override
  void initState() {
    super.initState();
    _load();
  }
  
  void _load() async {
    list = await DBHelper.instance.getAllInspections();
    setState(() {});
  }

  void _shareReport(Inspection ins) {
    final text = '''
📊 تقرير فحص الكهرباء
📅 التاريخ: ${ins.end}
----------------------------
⚡ القراءة المركزية: ${Utils.n(ins.central)}
🔌 مجموع فوارق العدادات: ${Utils.n(ins.subTotal)}
🏢 أحمال مشتركة: ${Utils.n(ins.shared)}
💡 إنارة: ${Utils.n(ins.lighting)}
----------------------------
🚨 الفاقد: ${Utils.n(ins.loss)}
📉 النسبة: ${ins.lossPercent.toStringAsFixed(2)}%
⚠️ الحالة: ${Utils.riskName(ins.lossPercent)}
    ''';
    Share.share(text);
  }

  void _exportExcel() async {
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['النتائج'];
      
      sheetObject.appendRow([
        TextCellValue('التاريخ'),
        TextCellValue('المركزي'),
        TextCellValue('الفرعية'),
        TextCellValue('الأحمال'),
        TextCellValue('الإنارة'),
        TextCellValue('الفاقد'),
        TextCellValue('النسبة %'),
        TextCellValue('الحالة'),
      ]);

      for (var ins in list) {
        sheetObject.appendRow([
          TextCellValue(ins.end),
          DoubleCellValue(ins.central),
          DoubleCellValue(ins.subTotal),
          DoubleCellValue(ins.shared),
          DoubleCellValue(ins.lighting),
          DoubleCellValue(ins.loss),
          DoubleCellValue(ins.lossPercent),
          TextCellValue(Utils.riskName(ins.lossPercent)),
        ]);
      }

      var fileBytes = excel.save();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/excel_report.xlsx');
      await file.writeAsBytes(fileBytes!);
      
      await Share.shareXFiles([XFile(file.path)], text: 'تقرير فحص الكهرباء (Excel)');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في التصدير: $e')));
    }
  }

  void _exportPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      build: (ctx) => [
        pw.Header(level: 0, text: 'فحص الكهرباء - التقرير النهائي'),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['الفترة', 'المركزي', 'الفرعية', 'الفاقد', 'النسبة', 'الحالة'],
          data: list.map((i) => [
            i.end, Utils.n(i.central), Utils.n(i.subTotal), Utils.n(i.loss), '${i.lossPercent.toStringAsFixed(1)}%', Utils.riskName(i.lossPercent)
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'تم عمل وصناعة هذا البرنامج بواسطة :\nعبدالله الزبيري\n777704402\nمحطة العاصمة باور', 
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (f) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('النتيجة النهائية'),
        actions: [
          IconButton(onPressed: _exportExcel, icon: const Icon(Icons.table_view, color: Colors.green)),
          IconButton(onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf)),
        ],
      ),
      body: list.isEmpty 
          ? const Center(child: Text('لا توجد فحوصات'))
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final ins = list[i];
                final color = Utils.riskColor(ins.lossPercent);
                return Card(
                  child: ListTile(
                    title: Text('الفترة: ${ins.end}'),
                    subtitle: Text('الفاقد: ${Utils.n(ins.loss)} (${ins.lossPercent.toStringAsFixed(1)}%)'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(label: Text(Utils.riskName(ins.lossPercent), style: const TextStyle(fontSize: 10, color: Colors.white)), backgroundColor: color),
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.blue),
                          onPressed: () => _shareReport(ins),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
