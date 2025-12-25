import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:receiptscanner/models/receipt_data.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('receipts.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE receipts (
        id TEXT PRIMARY KEY,
        store_name TEXT,
        date_time TEXT,
        amount INTEGER,
        target_10 INTEGER,
        target_8 INTEGER,
        tax_10 INTEGER,
        tax_8 INTEGER,
        invoice_num TEXT,
        tel TEXT,
        raw_text TEXT,
        image_path TEXT
      )
    ''');
  }

  Future<void> insertReceipt(ReceiptData receipt) async {
    final db = await instance.database;
    await db.insert(
      'receipts',
      receipt.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ReceiptData>> getReceipts({
    DateTime? startDate,
    DateTime? endDate,
    int? minAmount,
    int? maxAmount,
  }) async {
    final db = await instance.database;
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (startDate != null) {
      whereClause += ' AND date_time >= ?';
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      whereClause += ' AND date_time <= ?';
      whereArgs.add(endOfDay.toIso8601String());
    }
    if (minAmount != null) {
      whereClause += ' AND amount >= ?';
      whereArgs.add(minAmount);
    }
    if (maxAmount != null) {
      whereClause += ' AND amount <= ?';
      whereArgs.add(maxAmount);
    }

    final result = await db.query(
      'receipts',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'date_time ASC',
    );
    return result.map((json) => ReceiptData.fromMap(json)).toList();
  }

  // 【修正】重複チェック (excludeIdを追加)
  // excludeId: 編集中などの場合、自分自身のIDを除外してチェックする
  Future<bool> checkDuplicate(DateTime date, int amount, {String? excludeId}) async {
    final db = await instance.database;
    final dateStr = date.toIso8601String();

    String whereClause = 'date_time = ? AND amount = ?';
    List<dynamic> whereArgs = [dateStr, amount];

    if (excludeId != null && excludeId.isNotEmpty) {
      whereClause += ' AND id != ?';
      whereArgs.add(excludeId);
    }

    final result = await db.query(
      'receipts',
      where: whereClause,
      whereArgs: whereArgs,
    );

    return result.isNotEmpty;
  }

  Future<void> deleteReceipt(String id) async {
    final db = await instance.database;
    await db.delete(
      'receipts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}