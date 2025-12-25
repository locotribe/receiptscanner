import 'package:intl/intl.dart';

class ReceiptData {
  String id;
  String storeName;
  DateTime? date;
  int? amount;

  // ▼ 追加: 対象額(税抜)
  int? targetAmount10;
  int? targetAmount8;

  int? taxAmount10;
  int? taxAmount8;
  String? invoiceNumber;
  String? tel;
  String rawText;
  String? imagePath;

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

  // オブジェクト -> Map (保存時)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_name': storeName,
      'date_time': date?.toIso8601String(),
      'amount': amount,
      'target_10': targetAmount10, // 追加
      'target_8': targetAmount8,   // 追加
      'tax_10': taxAmount10,
      'tax_8': taxAmount8,
      'invoice_num': invoiceNumber,
      'tel': tel,
      'raw_text': rawText,
      'image_path': imagePath,
    };
  }

  // Map -> オブジェクト (読み出し時)
  factory ReceiptData.fromMap(Map<String, dynamic> map) {
    return ReceiptData(
      id: map['id'] ?? '',
      storeName: map['store_name'] ?? '',
      date: map['date_time'] != null ? DateTime.parse(map['date_time']) : null,
      amount: map['amount'],
      targetAmount10: map['target_10'], // 追加
      targetAmount8: map['target_8'],   // 追加
      taxAmount10: map['tax_10'],
      taxAmount8: map['tax_8'],
      invoiceNumber: map['invoice_num'],
      tel: map['tel'],
      rawText: map['raw_text'] ?? '',
      imagePath: map['image_path'],
    );
  }
}