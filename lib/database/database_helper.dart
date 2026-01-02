// lib/database/database_helper.dart
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
      version: 4,
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

  /// OCRテキストとユーザー入力カテゴリーを学習する
  Future<void> updateCategoryLearning(String rawText, String category) async {
    if (category.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();

    // ノイズ除去: 数字、スペース、記号を削除して純粋な文字情報にする
    final cleanText = rawText.replaceAll(RegExp(r'[0-9\s¥,.\-%:;]'), '');
    if (cleanText.length < 2) return;

    // 2文字ごとのN-gramを生成して学習 (例: "牛乳" -> "牛乳")
    for (int i = 0; i < cleanText.length - 1; i++) {
      final gram = cleanText.substring(i, i + 2);

      // 古いSQLiteバージョンでも動作するように UPSERT (ON CONFLICT DO UPDATE) を使わず、
      // INSERT OR IGNORE と UPDATE の組み合わせで実装する

      // 1. 初期値0で挿入（既に存在する場合は何もしない）
      batch.rawInsert('''
        INSERT OR IGNORE INTO category_learning (keyword, category, score)
        VALUES (?, ?, 0)
      ''', [gram, category]);

      // 2. スコアを加算（新規作成直後なら 0->1、既存なら score->score+1）
      batch.rawUpdate('''
        UPDATE category_learning
        SET score = score + 1
        WHERE keyword = ? AND category = ?
      ''', [gram, category]);
    }
    await batch.commit(noResult: true);
  }

  /// OCRテキストから最も可能性の高いカテゴリーを予測する
  Future<String?> predictCategory(String rawText) async {
    final db = await instance.database;
    final cleanText = rawText.replaceAll(RegExp(r'[0-9\s¥,.\-%:;]'), '');
    if (cleanText.length < 2) return null;

    // テキストから2文字ごとのキーワードを生成
    List<String> grams = [];
    for (int i = 0; i < cleanText.length - 1; i++) {
      grams.add(cleanText.substring(i, i + 2));
    }
    if (grams.isEmpty) return null;

    // 該当するキーワードの学習データを取得
    final placeholders = List.filled(grams.length, '?').join(',');
    final result = await db.query(
      'category_learning',
      where: 'keyword IN ($placeholders)',
      whereArgs: grams,
    );

    if (result.isEmpty) return null;

    // カテゴリーごとのスコアを集計
    Map<String, int> scores = {};
    for (var row in result) {
      final cat = row['category'] as String;
      final score = row['score'] as int;
      scores[cat] = (scores[cat] ?? 0) + score;
    }

    if (scores.isEmpty) return null;

    // 最もスコアが高いカテゴリーを返す
    var sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }
}