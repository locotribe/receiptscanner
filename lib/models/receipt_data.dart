import 'package:intl/intl.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ReceiptData {
  String id;
  String storeName;
  DateTime? date;
  int? amount;

  int? targetAmount10;
  int? targetAmount8;

  int? taxAmount10;
  int? taxAmount8;
  String? invoiceNumber;
  String? tel;
  String rawText;
  String? imagePath;

  // 摘要（科目）
  String? description;

  // 【追加】メモ（自由記述）
  String? memo;

  // 0: 未アップロード/変更あり, 1: アップロード済み
  int isUploaded;
  // Googleドライブ上のファイルID (上書きや重複チェック用)
  String? driveFileId;

  // PDF生成用にOCRの生データを一時保持する (DBには保存しない)
  RecognizedText? ocrData;

  // 複数枚撮影時のソース画像パスリスト (一時保持用)
  List<String>? sourceImagePaths;
  // 複数枚撮影時のOCRデータリスト (PDF生成用・一時保持用)
  List<RecognizedText>? sourceOcrData;

  ReceiptData({
    this.id = '',
    this.storeName = '',
    this.date,
    this.amount,
    this.targetAmount10,
    this.targetAmount8,
    this.taxAmount10,
    this.taxAmount8,
    this.invoiceNumber,
    this.tel,
    this.rawText = '',
    this.imagePath,
    this.description,
    this.memo, // 【追加】
    this.isUploaded = 0,
    this.driveFileId,
    this.ocrData,
    this.sourceImagePaths,
    this.sourceOcrData,
  });

  String get dateString {
    if (date == null) return '';
    return DateFormat('yyyy-MM-dd').format(date!);
  }

  String get timeString {
    if (date == null) return '';
    return DateFormat('HH:mm').format(date!);
  }

  String get amountFormatted {
    if (amount == null) return '';
    return NumberFormat("#,###").format(amount);
  }

  // DB保存用
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_name': storeName,
      'date_time': date?.toIso8601String(),
      'amount': amount,
      'target_10': targetAmount10,
      'target_8': targetAmount8,
      'tax_10': taxAmount10,
      'tax_8': taxAmount8,
      'invoice_num': invoiceNumber,
      'tel': tel,
      'raw_text': rawText,
      'image_path': imagePath,
      'description': description,
      'memo': memo, // 【追加】
      'is_uploaded': isUploaded,
      'drive_file_id': driveFileId,
    };
  }

  // DB読み込み用
  factory ReceiptData.fromMap(Map<String, dynamic> map) {
    return ReceiptData(
      id: map['id'] ?? '',
      storeName: map['store_name'] ?? '',
      date: map['date_time'] != null ? DateTime.parse(map['date_time']) : null,
      amount: map['amount'],
      targetAmount10: map['target_10'],
      targetAmount8: map['target_8'],
      taxAmount10: map['tax_10'],
      taxAmount8: map['tax_8'],
      invoiceNumber: map['invoice_num'],
      tel: map['tel'],
      rawText: map['raw_text'] ?? '',
      imagePath: map['image_path'],
      description: map['description'],
      memo: map['memo'], // 【追加】
      isUploaded: map['is_uploaded'] ?? 0,
      driveFileId: map['drive_file_id'],
    );
  }

  // Googleドライブ同期用 JSON変換
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'storeName': storeName,
      'date': date?.toIso8601String(),
      'amount': amount,
      'targetAmount10': targetAmount10,
      'targetAmount8': targetAmount8,
      'taxAmount10': taxAmount10,
      'taxAmount8': taxAmount8,
      'invoiceNumber': invoiceNumber,
      'tel': tel,
      'description': description,
      'memo': memo, // 【修正】明確にmemoフィールドとして保存
      'driveFileId': driveFileId,
    };
  }

  // JSON復元
  factory ReceiptData.fromJson(Map<String, dynamic> json) {
    return ReceiptData(
      id: json['id'],
      date: json['date'] != null ? DateTime.tryParse(json['date']) : null,
      storeName: json['storeName'] ?? '',
      amount: json['amount'],
      targetAmount10: json['targetAmount10'],
      targetAmount8: json['targetAmount8'],
      taxAmount10: json['taxAmount10'],
      taxAmount8: json['taxAmount8'],
      invoiceNumber: json['invoiceNumber'],
      tel: json['tel'],
      description: json['description'],
      memo: json['memo'], // 【追加】
      imagePath: null,
      isUploaded: (json['driveFileId'] != null) ? 1 : 0,
      driveFileId: json['driveFileId'],
    );
  }
}