// lib/logic/parser/extractors/amount_extractor.dart
import '../receipt_text_util.dart';

class AmountExtractor {
  /// 合計金額の決定ロジック
  static int? extract(List<String> lines, int? anchorTax, bool isDiesel) {
    print('[DEBUG] [Amount] --- 合計金額決定ロジック開始 (isDiesel: $isDiesel, AnchorTax: $anchorTax) ---');
    Map<int, int> scores = {};
    final amountPattern = RegExp(r'([¥\\])\s*([0-9,]+)');
    final plainNumberPattern = RegExp(r'(?<![\d])([0-9,]+)(?![\d])');

    final totalKeywords = ['合計', '小計', 'お買上', '支払', '合　計', 'お釣り', '楽天', 'Pay'];
    final excludeKeywords = ['No', 'ID', '端末', '番号', '会員', 'ポイント', 'SSPay'];

    for (var line in lines) {
      String norm = ReceiptTextUtil.normalizeAmountText(line);

      // キーワード判定の強化: スペースを除去してからチェック
      String checkLine = line.replaceAll(' ', '');

      if (excludeKeywords.any((k) => checkLine.contains(k))) {
        continue;
      }

      // 「合 計」のようにスペースが入っていてもヒットさせる
      bool isTotalLine = totalKeywords.any((k) => checkLine.contains(k));
      bool hasYenMark = norm.contains('¥') || norm.contains('\\');

      // 1. ¥マーク付き
      final yenMatches = amountPattern.allMatches(norm);
      for (var m in yenMatches) {
        String rawNumPart = m.group(2)!;
        List<int> extractedVals = ReceiptTextUtil.extractValues(rawNumPart);

        for (var val in extractedVals) {
          if (val == 0) continue;
          int score = 20;
          if (isTotalLine) score += 50;
          if (hasYenMark) score += 20;

          scores[val] = (scores[val] ?? 0) + score;
          print('[DEBUG] [Amount] 候補検出: $val (Score: +$score -> ${scores[val]}, Reason: ${isTotalLine ? "TotalKey" : ""} ${hasYenMark ? "YenMark" : ""})');
        }
      }

      // 2. キーワード行
      if (isTotalLine) {
        final plainMatches = plainNumberPattern.allMatches(norm.replaceAll('¥', ''));
        for (var m in plainMatches) {
          List<int> extractedVals = ReceiptTextUtil.extractValues(m.group(1)!);
          for (var val in extractedVals) {
            if (val == 0) continue;
            int score = 30;
            scores[val] = (scores[val] ?? 0) + score;
            print('[DEBUG] [Amount] 候補検出(KeyLine): $val (Score: +$score -> ${scores[val]})');
          }
        }
      }

      // 3. バックアップ
      final allMatches = plainNumberPattern.allMatches(norm.replaceAll('¥', ''));
      for (var m in allMatches) {
        List<int> extractedVals = ReceiptTextUtil.extractValues(m.group(1)!);
        for (var val in extractedVals) {
          if (val > 100 && val < 1000000) {
            scores[val] = (scores[val] ?? 0) + 1;
          }
        }
      }
    }

    int? bestAmount;
    int maxScore = -1;

    scores.forEach((amount, score) {
      if (amount > 10000000) return;

      if (anchorTax != null && anchorTax > 0) {
        double estimatedTax = amount * 0.10;
        double estimatedTax8 = amount * 0.08;
        double tolerance = isDiesel ? (amount * 0.05 + 500) : (amount * 0.02 + 5);
        double estimatedInnerTax8 = amount * 8 / 108;
        double estimatedInnerTax10 = amount * 10 / 110;

        bool isConsistent = false;

        if ((estimatedTax - anchorTax).abs() < tolerance ||
            (estimatedTax8 - anchorTax).abs() < tolerance ||
            (estimatedInnerTax8 - anchorTax).abs() < 5 ||
            (estimatedInnerTax10 - anchorTax).abs() < 5
        ) {
          isConsistent = true;
        }

        if (isDiesel) {
          if (amount > anchorTax * 5) {
            isConsistent = true;
          } else {
            isConsistent = false;
          }
        } else {
          if (estimatedTax > anchorTax * 3 && !isConsistent) {
            isConsistent = false;
          }
        }

        if (!isConsistent) {
          print('[DEBUG] [Amount] 棄却: $amount (Tax不整合 Anchor:$anchorTax)');
          return;
        }
      }

      if (score > maxScore) {
        maxScore = score;
        bestAmount = amount;
      } else if (score == maxScore) {
        if (bestAmount != null && amount > bestAmount!) {
          bestAmount = amount;
        }
      }
    });

    print('[DEBUG] [Amount] 合計金額決定: $bestAmount');
    return bestAmount;
  }
}