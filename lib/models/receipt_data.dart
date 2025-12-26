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

  // 【追加】アップロード状態管理用
  // 0: 未アップロード/変更あり, 1: アップロード済み
  int isUploaded;
  // Googleドライブ上のファイルID (上書きや重複チェック用)
  String? driveFileId;

  // PDF生成用にOCRの生データを一時保持する (DBには保存しない)
  RecognizedText? ocrData;

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
    this.isUploaded = 0, // デフォルトは「未」
    this.driveFileId,
    this.ocrData,
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
      // 【追加】DB保存用
      'is_uploaded': isUploaded,
      'drive_file_id': driveFileId,
    };
  }

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
      // 【追加】読み出し用 (nullの場合は0扱い)
      isUploaded: map['is_uploaded'] ?? 0,
      driveFileId: map['drive_file_id'],
    );
  }
}