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

  // 重複チェック
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

  // 【追加】電話番号から、過去に登録された最新の「店名」を取得する
  // ハイフンの有無による揺れを吸収するため、ハイフンを除去して比較する
  Future<String?> getStoreNameByTel(String tel) async {
    final db = await instance.database;

    // 検索する電話番号からハイフン等の記号を除去 (数字のみにする)
    final cleanTel = tel.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanTel.length < 9) return null; // 短すぎる番号は信頼しない

    // データベース内の全データを検索するのは重いため、直近のものを探す
    // ※SQLiteの関数でreplaceができれば良いが、アプリ側でフィルタリングする方が確実

    final result = await db.query(
      'receipts',
      columns: ['tel', 'store_name'],
      orderBy: 'date_time DESC', // 新しい順
    );

    for (var row in result) {
      final dbTel = (row['tel'] as String?) ?? '';
      final dbStore = (row['store_name'] as String?) ?? '';

      // DBの電話番号も数字のみにして比較
      final cleanDbTel = dbTel.replaceAll(RegExp(r'[^0-9]'), '');

      if (cleanDbTel == cleanTel && dbStore.isNotEmpty) {
        return dbStore; // ヒットしたらその店名を返す
      }
    }
    return null;
  }
}