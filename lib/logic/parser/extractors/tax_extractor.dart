// lib/logic/parser/extractors/tax_extractor.dart
import '../receipt_text_util.dart';

class TaxResult {
  final int? target10;
  final int? target8;
  final int? tax10;
  final int? tax8;

  TaxResult({this.target10, this.target8, this.tax10, this.tax8});
}

class TaxExtractor {
  /// レシート内で最も確からしい「消費税額」を探す (合計金額特定のヒント用)
  static int? findAnchorTax(List<String> lines) {
    print('[DEBUG] [Tax] --- 消費税額(AnchorTax)探索開始 ---');
    final taxKeywords = ['内税', '消費税', '税額', '税等', 'Tax', '10%', '8%'];

    int? bestTax;

    for (var line in lines) {
      String norm = ReceiptTextUtil.normalizeAmountText(line);
      // キーワード判定時にスペースを除去して判定
      String checkLine = norm.replaceAll(' ', '');
      bool hasKeyword = taxKeywords.any((k) => checkLine.contains(k));

      if (hasKeyword) {
        if (norm.contains('対象') || norm.contains('対縁')) {
          continue;
        }

        String textForExtraction = norm.replaceAll(RegExp(r'[0-9０-９]+[%％]'), '');
        List<int> vals = ReceiptTextUtil.extractValues(textForExtraction);
        for (var val in vals) {
          if (val > 0 && val < 50000) {
            if (bestTax == null || (val < bestTax)) {
              bestTax = val;
            }
          }
        }
      }
    }
    print('[DEBUG] [Tax] 決定した消費税額アンカー: ${bestTax ?? "なし"}');
    return bestTax;
  }

  /// 合計金額確定後の詳細な税額計算ロジック
  static TaxResult extract(List<String> lines, int amount, bool isDiesel) {
    print('[DEBUG] [Tax] --- 税額詳細計算開始 (Amount: $amount, isDiesel: $isDiesel) ---');

    int? target8;
    int? target10;
    int? tax8;
    int? tax10;

    if (isDiesel) {
      final dieselTargetPattern = RegExp(r'(10%|１０％).*?(対.|計|税抜|外税).*?([0-9,]+)');
      for (var line in lines) {
        String norm = ReceiptTextUtil.normalizeAmountText(line);
        final match = dieselTargetPattern.firstMatch(norm);
        if (match != null) {
          List<int> vals = ReceiptTextUtil.extractValues(match.group(0)!);
          vals.removeWhere((v) => v == 10 || v == 8);
          if (vals.isNotEmpty) {
            vals.sort();
            int candidate = vals.last;
            if (candidate > amount) continue;
            target10 = candidate;
            print('[DEBUG] [Tax] 軽油対象額検出: $target10');
            break;
          }
        }
      }
      if (target10 != null) {
        final dieselTaxPattern = RegExp(r'(10%|１０％).*?(税|Tax).*?([¥\\])?.*?([0-9,]+)');
        for (var line in lines) {
          String norm = ReceiptTextUtil.normalizeAmountText(line);
          if (!norm.contains('10%') && !norm.contains('１０％')) continue;
          if (norm.contains('対象') || norm.contains('対縁')) continue;
          final match = dieselTaxPattern.firstMatch(norm);
          if (match != null) {
            List<int> vals = ReceiptTextUtil.extractValues(norm);
            vals.removeWhere((v) => v == 10 || v == 8);
            if (vals.isNotEmpty) {
              vals.sort();
              int candidateTax = vals.first;
              if ((target10 * 0.1 - candidateTax).abs() < target10 * 0.05) {
                tax10 = candidateTax;
                print('[DEBUG] [Tax] 軽油税額検出: $tax10');
                break;
              }
            }
          }
        }
        if (tax10 == null) {
          tax10 = (target10 * 0.1).floor();
          print('[DEBUG] [Tax] 軽油税額自動計算: $tax10');
        }
        target8 = 0;
        tax8 = 0;
      }
    } else {
      List<int> candidates8 = [];
      List<int> candidates10 = [];
      final pattern8 = RegExp(r'(8%|８％|軽減|軽|8え|8X|8x).*?(対象|計|税抜|外税|課税).*?([0-9,]+)');
      final pattern10 = RegExp(r'(10%|１０％|標準).*?(対象|計|税抜|外税|課税).*?([0-9,]+)');
      final pattern8_B = RegExp(r'(内課税|課税).*?(8%|8え|8X|8x).*?([0-9,]+)');

      for (var line in lines) {
        String norm = ReceiptTextUtil.normalizeAmountText(line);
        if (pattern8.hasMatch(norm)) {
          var vals = ReceiptTextUtil.extractValues(norm);
          vals.removeWhere((v) => v == 8 || v == 10);
          candidates8.addAll(vals);
        }
        if (pattern8_B.hasMatch(norm)) {
          var vals = ReceiptTextUtil.extractValues(norm);
          vals.removeWhere((v) => v == 8 || v == 10);
          candidates8.addAll(vals);
        }
        if (pattern10.hasMatch(norm)) {
          var vals = ReceiptTextUtil.extractValues(norm);
          vals.removeWhere((v) => v == 10 || v == 8);
          candidates10.addAll(vals);
        }
      }

      bool resolved = false;
      if (!resolved && candidates8.contains(amount)) {
        target8 = amount; target10 = 0; resolved = true;
        print('[DEBUG] [Tax] 8%対象額と合計一致: $target8');
      } else if (!resolved && candidates10.contains(amount)) {
        target10 = amount; target8 = 0; resolved = true;
        print('[DEBUG] [Tax] 10%対象額と合計一致: $target10');
      }
      if (!resolved) {
        for (var val in candidates8) {
          if ((val * 1.08 - amount).abs() <= 1) {
            target8 = amount; target10 = 0; resolved = true; break;
          }
        }
      }
      if (!resolved) {
        for (var val in candidates10) {
          if ((val * 1.10 - amount).abs() <= 1) {
            target10 = amount; target8 = 0; resolved = true; break;
          }
        }
      }
      if (!resolved) {
        target10 = amount; target8 = 0;
        print('[DEBUG] [Tax] デフォルトで10%適用: $target10');
      }

      if (target8 != null && target8 > 0) tax8 = (target8 * 8 / 108).floor();
      if (target10 != null && target10 > 0) tax10 = (target10 * 10 / 110).floor();
    }

    return TaxResult(
      target10: target10,
      target8: target8,
      tax10: tax10,
      tax8: tax8,
    );
  }
}