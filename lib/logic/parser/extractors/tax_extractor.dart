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
  /// 税率に関連するOCR誤読を補正する
  static String _normalizeLine(String line) {
    String norm = ReceiptTextUtil.normalizeAmountText(line);
    // B% -> 8%, S% -> 5% などの補正
    norm = norm.replaceAllMapped(RegExp(r'([BSZOQDIlb369&])\s*[%％]'), (match) {
      String char = match.group(1)!;
      String fixed = char;
      switch (char) {
        case 'B': case '3': case '&': fixed = '8'; break; // 3や&も8の誤読として拾う
        case 'S': case '5': case '6': fixed = '8'; break; // 5/6も8の誤読の可能性が高い(文脈依存だが一旦8へ)
        case 'Z': fixed = '2'; break;
        case 'O': case 'Q': case 'D': fixed = '0'; break;
        case 'I': case 'l': case '|': fixed = '1'; break;
        case 'b': fixed = '6'; break;
        case '9': fixed = '8'; break; // 8%が9%に見えるケース対応
      }
      return '$fixed%';
    });
    // "80/0" や "8 96" のような%の誤読パターンを補正
    norm = norm.replaceAll(RegExp(r'8\s*[0oOQ]/[0oOQ]'), '8%');
    norm = norm.replaceAll(RegExp(r'8\s*96'), '8%');

    return norm;
  }

  /// 合計金額確定後の詳細な税額計算ロジック
  static TaxResult extract(List<String> lines, int amount, bool isDiesel) {
    print('[DEBUG] [Tax] --- 税額詳細計算開始 (Amount: $amount, isDiesel: $isDiesel) ---');

    int? target8;
    int? target10;
    int? tax8;
    int? tax10;

    // -------------------------------------------------------------------------
    // 戦略1: 文字列パターンマッチング (正規表現)
    // -------------------------------------------------------------------------
    if (isDiesel) {
      // (軽油のロジックは変更なし)
      final dieselTargetPattern = RegExp(r'(10%|１０％).*?(対.|計|税抜|外税).*?([0-9,]+)');
      for (var line in lines) {
        String norm = _normalizeLine(line);
        final match = dieselTargetPattern.firstMatch(norm);
        if (match != null) {
          List<int> vals = ReceiptTextUtil.extractValues(match.group(0)!);
          vals.removeWhere((v) => v == 10 || v == 8);
          if (vals.isNotEmpty) {
            vals.sort();
            int candidate = vals.last;
            if (candidate > amount) continue;
            target10 = candidate;
            break;
          }
        }
      }
      if (target10 != null) {
        final dieselTaxPattern = RegExp(r'(10%|１０％).*?(税|Tax).*?([¥\\])?.*?([0-9,]+)');
        for (var line in lines) {
          String norm = _normalizeLine(line);
          if (!norm.contains('10%') && !norm.contains('１０％')) continue;
          if (norm.contains('対象') || norm.contains('対縁')) continue;
          final match = dieselTaxPattern.firstMatch(norm);
          if (match != null) {
            List<int> vals = ReceiptTextUtil.extractValues(norm);
            vals.removeWhere((v) => v == 10 || v == 8);
            if (vals.isNotEmpty) {
              vals.sort();
              int candidateTax = vals.first;
              if ((target10 * 0.1 - candidateTax).abs() < target10 * 0.05 + 5) {
                tax10 = candidateTax;
                break;
              }
            }
          }
        }
        if (tax10 == null) tax10 = (target10 * 0.1).floor();
        target8 = 0;
        tax8 = 0;
      }
    } else {
      // 通常レシート
      List<int> candidates8 = [];
      List<int> candidates10 = [];

      final pattern8 = RegExp(r'(8%|８％|軽減|軽|8え|8X|8x).*?(対象|計|税抜|外税|課税|税率|内税|消費税).*?([0-9,]+)');
      final pattern10 = RegExp(r'(10%|１０％|標準).*?(対象|計|税抜|外税|課税|税率|内税|消費税).*?([0-9,]+)');
      final pattern8_B = RegExp(r'(内課税|課税|対象|計|税抜|外税|税率|内税|消費税).*?(8%|８％|軽減|軽|8え|8X|8x).*?([0-9,]+)');

      for (var line in lines) {
        String norm = _normalizeLine(line);

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

      // マッチング判定
      bool resolved = false;
      if (!resolved && candidates8.contains(amount)) {
        target8 = amount; target10 = 0; resolved = true;
        print('[DEBUG] [Tax] 8%対象額と合計一致(Regex): $target8');
      } else if (!resolved && candidates10.contains(amount)) {
        target10 = amount; target8 = 0; resolved = true;
        print('[DEBUG] [Tax] 10%対象額と合計一致(Regex): $target10');
      }

      if (!resolved) {
        // 近似値チェック
        for (var val in candidates8) {
          if ((val * 1.08 - amount).abs() <= 1 || val == amount) {
            target8 = amount; target10 = 0; resolved = true; break;
          }
        }
      }
      if (!resolved) {
        for (var val in candidates10) {
          if ((val * 1.10 - amount).abs() <= 1 || val == amount) {
            target10 = amount; target8 = 0; resolved = true; break;
          }
        }
      }

      // -----------------------------------------------------------------------
      // 戦略2: 数学的逆算アプローチ (Regex失敗時の最終手段)
      // 文字が読めなくても、合計金額から計算した「税額」がレシート内に存在するか探す
      // -----------------------------------------------------------------------
      if (!resolved && amount > 0) {
        print('[DEBUG] [Tax] Regex判定失敗 -> 数学的逆算(MathMatching)を実行');

        // 8%の場合の理論上の税額 (内税計算)
        int estimatedTax8 = (amount * 8 / 108).floor();
        // 10%の場合の理論上の税額 (内税計算)
        int estimatedTax10 = (amount * 10 / 110).floor();

        bool foundTax8 = false;
        bool foundTax10 = false;

        // 全行スキャンして理論値があるか探す
        for (var line in lines) {
          List<int> vals = ReceiptTextUtil.extractValues(line);
          if (estimatedTax8 > 0 && vals.contains(estimatedTax8)) foundTax8 = true;
          if (estimatedTax10 > 0 && vals.contains(estimatedTax10)) foundTax10 = true;
        }

        if (foundTax8 && !foundTax10) {
          // 8%の税額(54円)だけが見つかった -> 8%確定
          target8 = amount; target10 = 0;
          tax8 = estimatedTax8; tax10 = 0;
          resolved = true;
          print('[DEBUG] [Tax] MathMatching: 8%税額($estimatedTax8)を発見 -> 8%適用');
        } else if (foundTax10 && !foundTax8) {
          // 10%の税額だけが見つかった -> 10%確定
          target10 = amount; target8 = 0;
          tax10 = estimatedTax10; tax8 = 0;
          resolved = true;
          print('[DEBUG] [Tax] MathMatching: 10%税額($estimatedTax10)を発見 -> 10%適用');
        } else if (foundTax8 && foundTax10) {
          // 両方見つかった場合（稀だが）、8%キーワード（軽減、軽、*など）があるか追加チェック
          bool has8Key = lines.any((l) => l.contains('軽') || l.contains('*') || l.contains('※'));
          if (has8Key) {
            target8 = amount; target10 = 0; tax8 = estimatedTax8; resolved = true;
            print('[DEBUG] [Tax] MathMatching: 両方発見だが軽減キーワードあり -> 8%適用');
          }
        }
      }

      // それでも決まらなければデフォルト10%
      if (!resolved) {
        target10 = amount; target8 = 0;
        print('[DEBUG] [Tax] デフォルトで10%適用: $target10');
      }

      // 税額計算 (まだ計算されていない場合)
      if (tax8 == null && target8 != null && target8 > 0) tax8 = (target8 * 8 / 108).floor();
      if (tax10 == null && target10 != null && target10 > 0) tax10 = (target10 * 10 / 110).floor();
    }

    return TaxResult(
      target10: target10,
      target8: target8,
      tax10: tax10,
      tax8: tax8,
    );
  }

  // findAnchorTax メソッドは今回は AmountExtractor への影響だけなので
  // 以前のままでも問題ありませんが、必要であれば前の回答のコードを使ってください。
  // 最も重要なのは上記の extract メソッドの修正です。
  static int? findAnchorTax(List<String> lines) {
    // (前回のコードと同じでOKですが、念のため記述しておきます)
    final taxKeywords = ['内税', '消費税', '税額', '税等', 'Tax', '10%', '8%', '税率'];
    int? bestTax;
    for (var line in lines) {
      String norm = _normalizeLine(line);
      String checkLine = norm.replaceAll(' ', '');
      bool hasKeyword = taxKeywords.any((k) => checkLine.contains(k));
      if (hasKeyword) {
        if (norm.contains('対象') || norm.contains('対縁')) continue;
        String textForExtraction = norm.replaceAll(RegExp(r'[0-9０-９]+[%％]'), '');
        List<int> vals = ReceiptTextUtil.extractValues(textForExtraction);
        for (var val in vals) {
          if (val > 0 && val < 50000) {
            if (bestTax == null || (val < bestTax)) bestTax = val;
          }
        }
      }
    }
    return bestTax;
  }
}