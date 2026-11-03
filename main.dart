import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

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

class Street {
  final int? id;
  final String name;
  final String? centralMeter;
  Street({this.id, required this.name, this.centralMeter});
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'central_meter': centralMeter};
  factory Street.fromMap(Map<String, dynamic> m) => Street(id: m['id'], name: m['name'], centralMeter: m['central_meter']);
}

class Meter {
  final int? id;
  final int streetId;
  final String meterNo;
  final String? subscriber;
  Meter({this.id, required this.streetId, required this.meterNo, this.subscriber});
  Map<String, dynamic> toMap() => {'id': id, 'street_id': streetId, 'meter_no': meterNo, 'subscriber': subscriber};
  factory Meter.fromMap(Map<String, dynamic> m) => Meter(id: m['id'], streetId: m['street_id'], meterNo: m['meter_no'], subscriber: m['subscriber']);
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

class DBHelper {
  static final DBHelper instance = DBHelper._();
  DBHelper._();
  static Database? _db;

  Future<Database> get db async {
    _db ??= await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'elec.db');
    return openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE streets(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, central_meter TEXT)');
      await db.execute('CREATE TABLE meters(id INTEGER PRIMARY KEY AUTOINCREMENT, street_id INTEGER, meter_no TEXT, subscriber TEXT)');
      await db.execute('CREATE TABLE inspections(id INTEGER PRIMARY KEY AUTOINCREMENT, street_id INTEGER, period_type TEXT, start TEXT, end TEXT, central REAL, sub_total REAL, shared REAL, lighting REAL, loss REAL, loss_percent REAL)');
      await db.execute('CREATE TABLE readings(id INTEGER PRIMARY KEY AUTOINCREMENT, inspection_id INTEGER, meter_id INTEGER, reading REAL)');
    });
  }

  // الشوارع
  Future<List<Street>> getStreets() async {
    final d = await db;
    final res = await d.query('streets');
    return res.map(Street.fromMap).toList();
  }
  
  Future<int> addStreet(String name, String central) async {
    final d = await db;
    return d.insert('streets', {'name': name, 'central_meter': central});
  }

  Future<int> updateStreet(Street s) async {
    final d = await db;
    return d.update('streets', s.toMap(), where: 'id = ?', whereArgs: [s.id]);
  }

  // العدادات
  Future<List<Meter>> getMeters(int streetId) async {
    final d = await db;
    final res = await d.query('meters', where: 'street_id = ?', whereArgs: [streetId]);
    return res.map(Meter.fromMap).toList();
  }

  Future<int> addMeter(int streetId, String no, String sub) async {
    final d = await db;
    return d.insert('meters', {'street_id': streetId, 'meter_no': no, 'subscriber': sub});
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

  // الفحوصات
  Future<Inspection?> getLastInspection(int streetId) async {
    final d = await db;
    final res = await d.query('inspections', where: 'street_id = ?', whereArgs: [streetId], orderBy: 'id DESC', limit: 1);
    if (res.isEmpty) return null;
    return Inspection.fromMap(res.first);
  }

  Future<void> saveInspection(Inspection ins, Map<int, double> readings) async {
    final d = await db;
    await d.transaction((txn) async {
      final insId = await txn.insert('inspections', ins.toMap());
      for (var e in readings.entries) {
        await txn.insert('readings', {'inspection_id': insId, 'meter_id': e.key, 'reading': e.value});
      }
    });
  }

  Future<List<Inspection>> getInspections() async {
    final d = await db;
    final res = await d.query('inspections', orderBy: 'id DESC');
    return res.map(Inspection.fromMap).toList();
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Street> streets = [];
  List<Inspection> ins = [];
  
  @override
  void initState() {
    super.initState();
    _load();
  }
  
  void _load() async {
    streets = await DBHelper.instance.getStreets();
    ins = await DBHelper.instance.getInspections();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('محطة العاصمة'), backgroundColor: Colors.green.shade100),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.green.shade50,
            child: const ListTile(
              leading: Icon(Icons.electric_meter, size: 40),
              title: Text('نظام مراجعة وحساب الفاقد', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('إدارة الشوارع، العدادات، والتقارير'),
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
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const StreetsScreen()));
              _load();
            },
            icon: const Icon(Icons.streetview),
            label: const Text('إدارة الشوارع والعدادات'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: Colors.grey.shade200, foregroundColor: Colors.black),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
              _load();
            },
            icon: const Icon(Icons.assessment),
            label: const Text('التقارير والنتائج النهائية'),
          ),
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
  const StreetsScreen({super.key});
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
    list = await DBHelper.instance.getStreets();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الشوارع')),
      body: ListView.builder(
        itemCount: list.length,
        itemBuilder: (context, i) {
          final s = list[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.signpost),
              title: Text(s.name),
              subtitle: Text('عداد مركزي: ${s.centralMeter ?? "—"}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _addDialog(existing: s),
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
        onPressed: () => _addDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addDialog({Street? existing}) {
    final name = TextEditingController(text: existing?.name ?? '');
    final cen = TextEditingController(text: existing?.centralMeter ?? '');
    showDialog(
      context: context, 
      builder: (BuildContext ctx) => AlertDialog(
      title: Text(existing == null ? 'إضافة شارع' : 'تعديل شارع'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الشارع')),
          TextField(controller: cen, decoration: const InputDecoration(labelText: 'رقم العداد المركزي')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () async {
            if (name.text.isNotEmpty) {
              if (existing == null) {
                await DBHelper.instance.addStreet(name.text, cen.text);
              } else {
                await DBHelper.instance.updateStreet(Street(id: existing.id, name: name.text, centralMeter: cen.text));
              }
              if (mounted) Navigator.pop(ctx);
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
      appBar: AppBar(title: Text(widget.street.name)),
      body: meters.isEmpty 
          ? const Center(child: Text('أضف عدادات للبدء'))
          : ListView.builder(
              itemCount: meters.length,
              itemBuilder: (context, i) {
                final m = meters[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.speed)),
                  title: Text('عداد ${m.meterNo}'),
                  subtitle: Text(m.subscriber ?? '—'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _addDialog(existing: m),
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
            onPressed: () => _addDialog(),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  void _addDialog({Meter? existing}) {
    final no = TextEditingController(text: existing?.meterNo ?? '');
    final sub = TextEditingController(text: existing?.subscriber ?? '');
    showDialog(
      context: context, 
      builder: (BuildContext ctx) => AlertDialog(
      title: Text(existing == null ? 'إضافة عداد' : 'تعديل عداد'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: no, decoration: const InputDecoration(labelText: 'رقم العداد')),
          TextField(controller: sub, decoration: const InputDecoration(labelText: 'اسم المشترك')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () async {
            if (no.text.isNotEmpty) {
              if (existing == null) {
                await DBHelper.instance.addMeter(widget.street.id!, no.text, sub.text);
              } else {
                await DBHelper.instance.updateMeter(Meter(id: existing.id, streetId: widget.street.id!, meterNo: no.text, subscriber: sub.text));
              }
              if (mounted) Navigator.pop(ctx);
              _load();
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    ));
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
  
  double prevCentral = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  void _preload() async {
    // جلب القراءة المركزية السابقة
    final lastIns = await DBHelper.instance.getLastInspection(widget.street.id!);
    if (lastIns != null) {
      prevCentral = lastIns.central;
    }

    // جلب القراءات السابقة للعدادات
    for (var m in widget.meters) {
      final last = await DBHelper.instance.getLastReading(m.id!);
      previousReads[m.id!] = last ?? 0;
      // نضع القراءة السابقة كقيمة افتراضية (لأنه إذا لم يقرأ يأخذ نفس السابقة)
      currentReads[m.id!] = TextEditingController(text: Utils.n(last ?? 0));
    }
    setState(() => isLoading = false);
  }

  double get currentCentral => double.tryParse(central.text) ?? 0;
  double get sharedVal => double.tryParse(shared.text) ?? 0;
  double get lightingVal => double.tryParse(lighting.text) ?? 0;

  // حساب الفوارق
  double get centralDiff => currentCentral - prevCentral;
  
  double get totalSubDiffs {
    double total = 0;
    for (var m in widget.meters) {
      final curr = double.tryParse(currentReads[m.id!]?.text ?? '0') ?? 0;
      final prev = previousReads[m.id!] ?? 0;
      total += (curr - prev);
    }
    return total;
  }

  // الفاقد = فارق المركزي - (فوارق العدادات + أحمال + إنارة)
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
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('القراءة المركزية السابقة: ${Utils.n(prevCentral)}', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(controller: central, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'القراءة المركزية الحالية', border: OutlineInputBorder()), onChanged: (_) => setState((){})),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: shared, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أحمال (للفترة)'), onChanged: (_) => setState((){}))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: lighting, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إنارة (للفترة)'), onChanged: (_) => setState((){}))),
                    ],
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: color.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('فارق المركزي:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(Utils.n(centralDiff), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('مجموع فوارق العدادات:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(Utils.n(totalSubDiffs), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(),
                  Text('الحالة: ${Utils.riskName(lossPct)}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
                  const Divider(),
                  Text('الفاقد: ${Utils.n(loss)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
                  Text('النسبة: ${lossPct.toStringAsFixed(2)}%', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('القراءات الحالية للعدادات:', style: TextStyle(fontWeight: FontWeight.bold)),
          ...widget.meters.map((m) {
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
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'الحالية'),
                        onChanged: (_) => setState((){}),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () async {
              final ins = Inspection(
                streetId: widget.street.id!, periodType: 'custom', start: DateTime.now().toString().split(' ')[0], end: DateTime.now().toString().split(' ')[0],
                central: currentCentral, subTotal: totalSubDiffs, shared: sharedVal, lighting: lightingVal, loss: loss, lossPercent: lossPct,
              );
              final rMap = {for (var e in currentReads.entries) e.key: double.tryParse(e.value.text) ?? 0};
              await DBHelper.instance.saveInspection(ins, rMap);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حفظ الفحص'),
          ),
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
    list = await DBHelper.instance.getInspections();
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
