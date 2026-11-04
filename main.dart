import 'package:flutter/material.dart';
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
      title: 'مراجعة الكهرباء',
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
    'id': id, 
    'user_id': userId, 
    'name': name, 
    'central_meter': centralMeter,
    'central_prev': centralPrev
  };
  
  factory Street.fromMap(Map<String, dynamic> m) => Street(
    id: m['id'], 
    userId: m['user_id'] ?? 1, 
    name: m['name'], 
    centralMeter: m['central_meter'],
    centralPrev: (m['central_prev'] as num?)?.toDouble() ?? 0.0
  );
}

class Meter {
  final int? id;
  final int streetId;
  final String meterNo;
  final String? subscriber;
  final double prevReading;
  
  Meter({this.id, required this.streetId, required this.meterNo, this.subscriber, this.prevReading = 0});
  
  Map<String, dynamic> toMap() => {
    'id': id, 
    'street_id': streetId, 
    'meter_no': meterNo, 
    'subscriber': subscriber,
    'prev_reading': prevReading
  };
  
  factory Meter.fromMap(Map<String, dynamic> m) => Meter(
    id: m['id'], 
    streetId: m['street_id'], 
    meterNo: m['meter_no'], 
    subscriber: m['subscriber'],
    prevReading: (m['prev_reading'] as num?)?.toDouble() ?? 0.0
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
    central: m['central'], subTotal: m['sub_total'], shared: m['shared'], lighting: m['lighting'],
    loss: m['loss'], lossPercent: m['loss_percent']
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
      version: 4, 
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
        await db.execute('CREATE TABLE streets(id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER DEFAULT 1, name TEXT, central_meter TEXT, central_prev REAL DEFAULT 0)');
        await db.execute('CREATE TABLE meters(id INTEGER PRIMARY KEY AUTOINCREMENT, street_id INTEGER, meter_no TEXT, subscriber TEXT, prev_reading REAL DEFAULT 0)');
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

  Future<List<Meter>> getMeters(int streetId) async {
    final d = await db;
    final res = await d.query('meters', where: 'street_id = ?', whereArgs: [streetId], orderBy: 'id ASC');
    return res.map(Meter.fromMap).toList();
  }

  Future<int> addMeter(int streetId, String no, String sub, double prevReading) async {
    final d = await db;
    return d.insert('meters', {'street_id': streetId, 'meter_no': no, 'subscriber': sub, 'prev_reading': prevReading});
  }

  Future<int> updateMeter(Meter m) async {
    final d = await db;
    return d.update('meters', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
  }

  Future<double?> getLastReading(int meterId) async {
    final d = await db;
    final res = await d.rawQuery('SELECT reading FROM readings WHERE meter_id = ? ORDER BY id DESC LIMIT 1', [meterId]);
    if (res.isEmpty) return null;
    return res.first['reading'] as double;
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

  Future<void> saveInspection(Inspection ins, Map<int, double> readings) async {
    final d = await db;
    await d.transaction((txn) async {
      final insId = await txn.insert('inspections', ins.toMap());
      for (var e in readings.entries) {
        await txn.insert('readings', {'inspection_id': insId, 'meter_id': e.key, 'reading': e.value});
      }
      
      await txn.update('streets', {'central_prev': ins.central}, where: 'id = ?', whereArgs: [ins.streetId]);
      for (var e in readings.entries) {
        await txn.update('meters', {'prev_reading': e.value}, where: 'id = ?', whereArgs: [e.key]);
      }
    });
  }

  Future<List<Inspection>> getAllInspections() async {
    final d = await db;
    final res = await d.query('inspections', orderBy: 'id DESC');
    return res.map(Inspection.fromMap).toList();
  }

  Future<String> backupData() async {
    final d = await db;
    final users = await d.query('users');
    final streets = await d.query('streets');
    final meters = await d.query('meters');
    final inspections = await d.query('inspections');
    final readings = await d.query('readings');
    return jsonEncode({
      'users': users,
      'streets': streets,
      'meters': meters,
      'inspections': inspections,
      'readings': readings,
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

      for (var row in data['users'] ?? []) {
        await txn.insert('users', Map<String, dynamic>.from(row));
      }
      for (var row in data['streets']) {
        await txn.insert('streets', Map<String, dynamic>.from(row));
      }
      for (var row in data['meters']) {
        await txn.insert('meters', Map<String, dynamic>.from(row));
      }
      for (var row in data['inspections']) {
        await txn.insert('inspections', Map<String, dynamic>.from(row));
      }
      for (var row in data['readings']) {
        await txn.insert('readings', Map<String, dynamic>.from(row));
      }
    });
  }
}

class Utils {
  static final fmt = NumberFormat('#,##0.##', 'en');
  static String n(num v) => fmt.format(v);
  
  static Color riskColor(double p) {
    if (p > 35) return Colors.red;
    if (p > 20) return Colors.orange;
    if (p > 10) return Colors.amber;
    return Colors.green;
  }
  
  static String riskName(double p) {
    if (p > 35) return 'خطر (سرقة محتملة)';
    if (p > 20) return 'مشكوك';
    if (p > 10) return 'تحذير';
    return 'طبيعي';
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
    setState(() {
      currentUser = user;
    });
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

  void _backup() async {
    try {
      final jsonStr = await DBHelper.instance.backupData();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/elec_backup.json');
      await file.writeAsString(jsonStr);
      await Share.shareXFiles([XFile(file.path)], text: 'نسخة احتياطية لتطبيق مراجعة الكهرباء');
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
        title: const Text('محطة العاصمة'), 
        backgroundColor: Colors.green.shade100,
        actions: [
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
              'تم صناعة هذا البرنامج بواسطة:\nعبدالله الزبيري\nDeepSeek مع Claude\nواشراف\nهيثم الابيض',
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
  
  @override
  void initState() {
    super.initState();
    _load();
  }
  
  void _load() async {
    list = await DBHelper.instance.getAllStreets();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الشوارع')),
      body: list.isEmpty 
        ? const Center(child: Text('لا توجد شوارع. أضف شارعاً جديداً.'))
        : ListView.builder(
        itemCount: list.length,
        itemBuilder: (context, i) {
          final s = list[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.signpost),
              title: Text(s.name),
              subtitle: Text('مركزي: ${s.centralMeter ?? "—"} | سابقة: ${Utils.n(s.centralPrev)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _addDialog(context, existing: s),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addDialog(BuildContext parentContext, {Street? existing}) {
    final name = TextEditingController(text: existing?.name ?? '');
    final cen = TextEditingController(text: existing?.centralMeter ?? '');
    final cenPrev = TextEditingController(text: existing != null ? Utils.n(existing.centralPrev) : '0');
    
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
            TextField(controller: cenPrev, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'القراءة المركزية السابقة')),
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
  
  @override
  void initState() {
    super.initState();
    _load();
  }
  
  void _load() async {
    meters = await DBHelper.instance.getMeters(widget.street.id!);
    setState(() {});
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
      body: meters.isEmpty 
          ? const Center(child: Text('أضف عدادات للبدء'))
          : ListView.builder(
              itemCount: meters.length,
              itemBuilder: (context, i) {
                final m = meters[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.speed)),
                  title: Text('عداد ${m.meterNo}'),
                  subtitle: Text('${m.subscriber ?? "—"} | السابقة: ${Utils.n(m.prevReading)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _addDialog(context, existing: m),
                  ),
                );
              },
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

  // الترقيم التلقائي للعداد
  void _addDialog(BuildContext parentContext, {Meter? existing}) {
    final sub = TextEditingController(text: existing?.subscriber ?? '');
    final prev = TextEditingController(text: existing != null ? Utils.n(existing.prevReading) : '0');
    final autoNo = existing?.meterNo ?? '${meters.length + 1}'; // الترقيم التلقائي
    
    showDialog(
      context: parentContext, 
      builder: (BuildContext ctx) => AlertDialog(
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
            TextField(controller: prev, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'القراءة السابقة للعداد')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () async {
            final pRead = double.tryParse(prev.text) ?? 0;
            if (existing == null) {
              await DBHelper.instance.addMeter(widget.street.id!, autoNo, sub.text, pRead);
            } else {
              await DBHelper.instance.updateMeter(Meter(id: existing.id, streetId: widget.street.id!, meterNo: autoNo, subscriber: sub.text, prevReading: pRead));
            }
            if (parentContext.mounted) Navigator.pop(ctx);
            _load();
          },
          child: const Text('حفظ'),
        ),
      ],
    ));
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
                     title: Text('التاريخ: ${ins.end}'),
                     subtitle: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text('المركزي: ${Utils.n(ins.central)}'),
                         Text('الفوارق: ${Utils.n(ins.subTotal)}'),
                         Text('الفاقد: ${Utils.n(ins.loss)} (${ins.lossPercent.toStringAsFixed(1)}%)', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
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
  const NewInspectionScreen({super.key, required this.street, required this.meters});
  @override
  State<NewInspectionScreen> createState() => _NewInspectionScreenState();
}

class _NewInspectionScreenState extends State<NewInspectionScreen> {
  final central = TextEditingController(text: '0');
  final shared = TextEditingController(text: '0');
  final lighting = TextEditingController(text: '0');
  
  Map<int, TextEditingController> currentReads = {};
  Map<int, double> previousReads = {};
  List<FocusNode> _focusNodes = []; // للتنقل بالكيبورد
  
  double prevCentral = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  @override
  void dispose() {
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _preload() async {
    final lastIns = await DBHelper.instance.getLastInspection(widget.street.id!);
    if (lastIns != null) {
      prevCentral = lastIns.central;
    } else {
      prevCentral = widget.street.centralPrev;
    }

    for (var m in widget.meters) {
      final last = await DBHelper.instance.getLastReading(m.id!);
      previousReads[m.id!] = last ?? m.prevReading;
      currentReads[m.id!] = TextEditingController(text: Utils.n(previousReads[m.id!]!));
      _focusNodes.add(FocusNode()); // إضافة نقطة تركيز لكل عداد
    }
    setState(() => isLoading = false);
  }

  double get currentCentral => double.tryParse(central.text) ?? 0;
  double get sharedVal => double.tryParse(shared.text) ?? 0;
  double get lightingVal => double.tryParse(lighting.text) ?? 0;

  double get centralDiff => currentCentral - prevCentral;
  
  double get totalPrevReadings {
    return previousReads.values.fold(0.0, (sum, val) => sum + val);
  }

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

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    final color = Utils.riskColor(lossPct);
    return Scaffold(
      appBar: AppBar(title: const Text('فحص جديد (فوارق)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
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
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'القراءة المركزية الحالية', border: OutlineInputBorder()), 
                    onChanged: (_) => setState((){})
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: shared, 
                          keyboardType: TextInputType.number, 
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
          // استخدام List.generate للتنقل بالكيبورد
          ...List.generate(widget.meters.length, (index) {
            final m = widget.meters[index];
            final prev = previousReads[m.id!] ?? 0;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('عداد ${m.meterNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(m.subscriber ?? '—', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          Text('السابقة: ${Utils.n(prev)}', style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: currentReads[m.id!],
                        focusNode: _focusNodes[index],
                        keyboardType: TextInputType.number,
                        textInputAction: index == widget.meters.length - 1 ? TextInputAction.done : TextInputAction.next,
                        onSubmitted: (_) {
                          if (index < widget.meters.length - 1) {
                            FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
                          } else {
                            FocusScope.of(context).unfocus();
                          }
                        },
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'الحالية'),
                        onChanged: (_) => setState((){}),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
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
                const Text('إجمالي السابقة:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(Utils.n(totalPrevReadings), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('إجمالي الحالية:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(Utils.n(totalCurrentReadings), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الفرق (المحسوب):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                Text(Utils.n(totalSubDiffs), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الفاقد التقديري:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('${Utils.n(loss)} (${lossPct.toStringAsFixed(1)}%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(45), backgroundColor: color),
              onPressed: () async {
                final ins = Inspection(
                  streetId: widget.street.id!, periodType: 'custom', start: DateTime.now().toString().split(' ')[0], end: DateTime.now().toString().split(' ')[0],
                  central: currentCentral, subTotal: totalSubDiffs, shared: sharedVal, lighting: lightingVal, loss: loss, lossPercent: lossPct,
                );
                final rMap = {for (var e in currentReads.entries) e.key: double.tryParse(e.value.text) ?? 0};
                await DBHelper.instance.saveInspection(ins, rMap);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('حفظ الفحص', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
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
📊 تقرير فحص كهرباء - محطة العاصمة
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
        pw.Header(level: 0, text: 'محطة العاصمة - التقرير النهائي'),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['الفترة', 'المركزي', 'الفرعية', 'الفاقد', 'النسبة', 'الحالة'],
          data: list.map((i) => [
            i.end, Utils.n(i.central), Utils.n(i.subTotal), Utils.n(i.loss), '${i.lossPercent.toStringAsFixed(1)}%', Utils.riskName(i.lossPercent)
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'تم صناعة هذا البرنامج بواسطة:\nعبدالله الزبيري\nDeepSeek مع Claude\nواشراف هيثم الابيض', 
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
