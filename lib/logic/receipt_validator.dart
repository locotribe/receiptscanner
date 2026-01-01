// lib/logic/receipt_validator.dart
import '../models/receipt_data.dart';

class ReceiptValidator {
  /// 税額情報の整合性をチェックし、必要に応じて自動補完・修正を行う
  static void refineTaxData(ReceiptData data) {
    if (data.amount != null && data.amount! > 0) {
      int total = data.amount!;

      // 10%税額の妥当性チェック (5%〜15%の範囲外なら無効化)
      if (data.taxAmount10 != null) {
        double rate = data.taxAmount10! / total;
        if (rate < 0.05 || rate > 0.15) data.taxAmount10 = null;
      }

      // 8%税額の妥当性チェック (4%〜12%の範囲外なら無効化)
      if (data.taxAmount8 != null) {
        double rate = data.taxAmount8! / total;
        if (rate < 0.04 || rate > 0.12) data.taxAmount8 = null;
      }

      // 税情報が全くない場合、デフォルトで10%内税として計算
      bool hasTaxInfo = data.targetAmount10 != null ||
          data.taxAmount10 != null ||
          data.targetAmount8 != null ||
          data.taxAmount8 != null;

      if (!hasTaxInfo) {
        int tax = (total * 10 / 110).floor();
        int target = total - tax;
        data.taxAmount10 = tax;
        data.targetAmount10 = target;
      }
    }
  }

  /// 読み取り結果に対する警告メッセージリストを生成する
  static List<String> getQualityWarnings(ReceiptData data) {
    List<String> warnings = [];

    // 金額チェック
    if (data.amount == null) {
      warnings.add('・合計金額が読み取れませんでした');
    } else if (data.amount! > 10000000) {
      warnings.add('・金額が異常に大きいです (${data.amountFormatted}円)');
    }

    // 日付チェック
    if (data.date == null) {
      warnings.add('・日付が読み取れませんでした');
    } else {
      final now = DateTime.now();
      // 未来の日付 (許容範囲: 明日まで)
      if (data.date!.isAfter(now.add(const Duration(days: 1)))) {
        warnings.add('・日付が未来になっています (${data.dateString})');
      }
      // 過去の日付 (許容範囲: 2000年以降)
      if (data.date!.year < 2000) {
        warnings.add('・日付が過去すぎます (${data.dateString})');
      }
    }

    return warnings;
  }
}