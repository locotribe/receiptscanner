import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/receipt_data.dart';

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
      // 【修正】バージョンを5に変更
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
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
        image_path TEXT,
        description TEXT,
        memo TEXT, -- 【追加】
        is_uploaded INTEGER DEFAULT 0,
        drive_file_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE category_learning (
        keyword TEXT,
        category TEXT,
        score INTEGER,
        PRIMARY KEY (keyword, category)
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE receipts ADD COLUMN is_uploaded INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE receipts ADD COLUMN drive_file_id TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE receipts ADD COLUMN description TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE category_learning (
          keyword TEXT,
          category TEXT,
          score INTEGER,
          PRIMARY KEY (keyword, category)
        )
      ''');
    }
    // 【追加】バージョン5へのアップグレード: memoカラムを追加
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE receipts ADD COLUMN memo TEXT');
    }
  }

  Future<void> insertReceipt(ReceiptData receipt) async {
    final db = await instance.database;
    await db.insert(
      'receipts',
      receipt.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateReceipt(ReceiptData receipt) async {
    final db = await instance.database;
    return await db.update(
      'receipts',
      receipt.toMap(),
      where: 'id = ?',
      whereArgs: [receipt.id],
    );
  }

  Future<void> updateUploadStatus(String id, String driveFileId) async {
    final db = await instance.database;
    await db.update(
      'receipts',
      {
        'is_uploaded': 1,
        'drive_file_id': driveFileId,
      },
      where: 'id = ?',
      whereArgs: [id],
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

  Future<String?> getStoreNameByTel(String tel) async {
    final db = await instance.database;
    final cleanTel = tel.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanTel.length < 9) return null;

    final result = await db.query(
      'receipts',
      columns: ['tel', 'store_name'],
      orderBy: 'date_time DESC',
    );

    for (var row in result) {
      final dbTel = (row['tel'] as String?) ?? '';
      final dbStore = (row['store_name'] as String?) ?? '';
      final cleanDbTel = dbTel.replaceAll(RegExp(r'[^0-9]'), '');

      if (cleanDbTel == cleanTel && dbStore.isNotEmpty) {
        return dbStore;
      }
    }
    return null;
  }

  Future<void> mergeReceipts(List<ReceiptData> cloudReceipts) async {
    final db = await instance.database;
    final batch = db.batch();

    for (var receipt in cloudReceipts) {
      final List<Map<String, dynamic>> existing = await db.query(
        'receipts',
        where: 'id = ?',
        whereArgs: [receipt.id],
      );

      if (existing.isEmpty) {
        batch.insert('receipts', receipt.toMap());
      } else {
        final currentLocalPath = existing.first['image_path'] as String?;
        var newData = receipt.toMap();
        newData['image_path'] = currentLocalPath;

        batch.update(
          'receipts',
          newData,
          where: 'id = ?',
          whereArgs: [receipt.id],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  // --- 学習機能用メソッド ---

  Future<void> updateCategoryLearning(String rawText, String category) async {
    if (category.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();

    final cleanText = rawText.replaceAll(RegExp(r'[0-9\s¥,.\-%:;]'), '');
    if (cleanText.length < 2) return;

    for (int i = 0; i < cleanText.length - 1; i++) {
      final gram = cleanText.substring(i, i + 2);

      batch.rawInsert('''
        INSERT OR IGNORE INTO category_learning (keyword, category, score)
        VALUES (?, ?, 0)
      ''', [gram, category]);

      batch.rawUpdate('''
        UPDATE category_learning
        SET score = score + 1
        WHERE keyword = ? AND category = ?
      ''', [gram, category]);
    }
    await batch.commit(noResult: true);
  }

  Future<String?> predictCategory(String rawText) async {
    final db = await instance.database;
    final cleanText = rawText.replaceAll(RegExp(r'[0-9\s¥,.\-%:;]'), '');
    if (cleanText.length < 2) return null;

    List<String> grams = [];
    for (int i = 0; i < cleanText.length - 1; i++) {
      grams.add(cleanText.substring(i, i + 2));
    }
    if (grams.isEmpty) return null;

    final placeholders = List.filled(grams.length, '?').join(',');
    final result = await db.query(
      'category_learning',
      where: 'keyword IN ($placeholders)',
      whereArgs: grams,
    );

    if (result.isEmpty) return null;

    Map<String, int> scores = {};
    for (var row in result) {
      final cat = row['category'] as String;
      final score = row['score'] as int;
      scores[cat] = (scores[cat] ?? 0) + score;
    }

    if (scores.isEmpty) return null;

    var sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }
}