// lib/logic/receipt_parser.dart
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:uuid/uuid.dart';
import '../models/receipt_data.dart';

class ReceiptParser {
  final _uuid = const Uuid();

  /// 座標情報を使って、同じ高さにあるテキストを1行に結合する
  /// (複数画像のマージ時のみ使用)
  List<String> _mergeLinesByCoordinate(RecognizedText recognizedText) {
    print('[DEBUG] --- 行結合処理開始 ---');
    List<TextLine> allLines = [];
    for (var block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }

    if (allLines.isEmpty) return [];

    // 1. まずY座標（top）で大まかにソート
    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    List<List<TextLine>> rows = [];

    // 2. 行（Y座標が近いもの）ごとにグルーピングする
    for (var line in allLines) {
      bool added = false;
      double lineHeight = line.boundingBox.height;
      double lineCenterY = line.boundingBox.center.dy;

      for (var row in rows) {
        if (row.isEmpty) continue;
        double rowCenterY = row.first.boundingBox.center.dy;

        // 許容誤差: 文字の高さの0.6倍程度
        if ((rowCenterY - lineCenterY).abs() < lineHeight * 0.6) {
          row.add(line);
          added = true;
          break;
        }
      }

      if (!added) {
        rows.add([line]);
      }
    }

    // 3. 各行の中で、X座標（left）順に並べ替えて結合する
    List<String> mergedLines = [];
    for (var row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      String mergedText = row.map((e) => e.text).join(' ');
      mergedLines.add(mergedText);
      // print('[DEBUG] Row: $mergedText');
    }
    print('[DEBUG] --- 行結合処理終了 (${mergedLines.length}行) ---');

    return mergedLines;
  }

  /// 2枚の画像のOCR結果から、重なり（オーバーラップ）を検出してスコアを算出する
  int _calculateOverlapScore(RecognizedText textA, RecognizedText textB) {
    final linesA = _mergeLinesByCoordinate(textA);
    final linesB = _mergeLinesByCoordinate(textB);
    if (linesA.isEmpty || linesB.isEmpty) return 0;

    final int checkCountA = (linesA.length * 0.3).ceil().clamp(3, 15);
    final int checkCountB = (linesB.length * 0.3).ceil().clamp(3, 15);

    final subA = linesA.sublist(max(0, linesA.length - checkCountA));
    final subB = linesB.sublist(0, min(linesB.length, checkCountB));

    int score = 0;
    for (var strA in subA) {
      if (strA.length < 3) continue;
      for (var strB in subB) {
        if (strB.length < 3) continue;
        if (strA == strB || strA.contains(strB) || strB.contains(strA)) {
          score += 10;
        } else {
          if (_areSimilar(strA, strB)) {
            score += 5;
          }
        }
      }
    }
    return score;
  }

  bool _areSimilar(String a, String b) {
    if ((a.length - b.length).abs() > 3) return false;
    int matchCount = 0;
    int len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      if (a[i] == b[i]) matchCount++;
    }
    return (matchCount / len) > 0.7;
  }

  /// 金額解析用の文字クリーニング
  String _normalizeAmountText(String text) {
    String s = text;
    s = s.replaceAllMapped(RegExp(r'[０-９]'), (m) => (m.group(0)!.codeUnitAt(0) - 0xFEE0).toString());
    s = s.replaceAll(RegExp(r',\s+'), ',');
    s = s.replaceAll(RegExp(r'[Yy]\s*(?=[0-9])'), '¥');
    s = s.replaceAll(RegExp(r'[Ww]\s*(?=[0-9])'), '¥');
    s = s.replaceAll(RegExp(r'(?<![0-9])4(?=[0-9]{1,3}(,|¥d{3}))'), '¥');
    s = s.replaceAll(RegExp(r'[\$\*＊]'), '');
    s = s.replaceAll('l', '1');
    s = s.replaceAll('O', '0');
    s = s.replaceAllMapped(RegExp(r'(\d)\s+([0-9])'), (Match m) => '${m.group(1)}${m.group(2)}');
    s = s.replaceAll(RegExp(r'\d+\s*[点個]'), '');
    return s;
  }

  /// 文字列から数値を抽出するヘルパー
  List<int> _extractValues(String text) {
    List<int> values = [];
    final matches = RegExp(r'[0-9,]+').allMatches(text);

    for (var m in matches) {
      String valStr = m.group(0)!.replaceAll(',', '');
      if (valStr.isEmpty) continue;

      int? val = int.tryParse(valStr);
      if (val != null) {
        values.add(val);
        if (valStr.length >= 3 && valStr.startsWith('4')) {
          String strippedStr = valStr.substring(1);
          int? strippedVal = int.tryParse(strippedStr);
          if (strippedVal != null && strippedVal > 0) {
            values.add(strippedVal);
          }
        }
      }
    }
    return values;
  }

  /// レシート内で最も確からしい「消費税額」を探す
  int? _findAnchorTax(List<String> lines) {
    print('[DEBUG] --- 消費税額(AnchorTax)探索開始 ---');
    final taxKeywords = ['内税', '消費税', '税額', '税等', 'Tax', '10%', '8%'];

    int? bestTax;

    for (var line in lines) {
      String norm = _normalizeAmountText(line);
      // 【修正】キーワード判定時にスペースを除去して判定
      String checkLine = norm.replaceAll(' ', '');
      bool hasKeyword = taxKeywords.any((k) => checkLine.contains(k));

      if (hasKeyword) {
        if (norm.contains('対象') || norm.contains('対縁')) {
          continue;
        }

        String textForExtraction = norm.replaceAll(RegExp(r'[0-9０-９]+[%％]'), '');
        List<int> vals = _extractValues(textForExtraction);
        for (var val in vals) {
          if (val > 0 && val < 50000) {
            if (bestTax == null || (val < bestTax)) {
              bestTax = val;
            }
          }
        }
      }
    }
    print('[DEBUG] 決定した消費税額アンカー: ${bestTax ?? "なし"}');
    return bestTax;
  }

  /// 合計金額の決定ロジック
  int? _determineTotalAmount(List<String> lines, int? anchorTax, bool isDiesel) {
    print('[DEBUG] --- 合計金額決定ロジック開始 (isDiesel: $isDiesel, AnchorTax: $anchorTax) ---');
    Map<int, int> scores = {};
    final amountPattern = RegExp(r'([¥\\])\s*([0-9,]+)');
    final plainNumberPattern = RegExp(r'(?<![\d])([0-9,]+)(?![\d])');

    final totalKeywords = ['合計', '小計', 'お買上', '支払', '合　計', 'お釣り', '楽天', 'Pay'];
    final excludeKeywords = ['No', 'ID', '端末', '番号', '会員', 'ポイント', 'SSPay'];

    for (var line in lines) {
      String norm = _normalizeAmountText(line);

      // 【修正】キーワード判定の強化: スペースを除去してからチェック
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
        List<int> extractedVals = _extractValues(rawNumPart);

        for (var val in extractedVals) {
          if (val == 0) continue;
          int score = 20;
          if (isTotalLine) score += 50; // ここが正しく加算されるようになる
          if (hasYenMark) score += 20;

          scores[val] = (scores[val] ?? 0) + score;
        }
      }

      // 2. キーワード行
      if (isTotalLine) {
        final plainMatches = plainNumberPattern.allMatches(norm.replaceAll('¥', ''));
        for (var m in plainMatches) {
          List<int> extractedVals = _extractValues(m.group(1)!);
          for (var val in extractedVals) {
            if (val == 0) continue;
            scores[val] = (scores[val] ?? 0) + 30; // ここも正しく加算される
          }
        }
      }

      // 3. バックアップ
      final allMatches = plainNumberPattern.allMatches(norm.replaceAll('¥', ''));
      for (var m in allMatches) {
        List<int> extractedVals = _extractValues(m.group(1)!);
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

        if (!isConsistent) return;
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

    print('[DEBUG] 合計金額決定: $bestAmount');
    return bestAmount;
  }

  /// 【修正】リスト対応版 parse メソッド
  ReceiptData parse(List<RecognizedText> recognizedTexts, List<String> imagePaths) {
    print('[DEBUG] ========== 解析開始 (Images: ${recognizedTexts.length}) ==========');

    List<RecognizedText> sortedOcrData = [];
    List<String> sortedImagePaths = [];
    List<String> allLines = [];

    // 【分岐】画像が1枚の場合と複数枚の場合で処理を分ける
    if (recognizedTexts.length == 1) {
      print('[DEBUG] Single Image Mode: 結合処理をスキップします');
      // 1枚の場合はそのまま使用 (ソートや結合ロジックを通さない)
      sortedOcrData = recognizedTexts;
      sortedImagePaths = imagePaths;

      // シンプルに行リストを抽出 (Y座標ソートのみ行う)
      List<TextLine> rawLines = [];
      for (var block in recognizedTexts.first.blocks) {
        rawLines.addAll(block.lines);
      }
      // Y座標順にソートして自然な読み順にする
      rawLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

      // 行結合(join)を行わず、そのままリスト化
      allLines = rawLines.map((l) => l.text).toList();

    } else {
      // 2枚以上の場合 (既存の結合ロジック)
      print('[DEBUG] Multi Image Mode: 結合・重複排除処理を実行します');

      // 1. 画像の順序判定
      if (recognizedTexts.length == 2) {
        final textA = recognizedTexts[0];
        final textB = recognizedTexts[1];
        int scoreAB = _calculateOverlapScore(textA, textB);
        int scoreBA = _calculateOverlapScore(textB, textA);

        if (scoreBA > scoreAB && scoreBA > 10) {
          sortedOcrData = [textB, textA];
          sortedImagePaths = [imagePaths[1], imagePaths[0]];
        } else {
          sortedOcrData = [textA, textB];
          sortedImagePaths = [imagePaths[0], imagePaths[1]];
        }
      } else {
        sortedOcrData = List.from(recognizedTexts);
        sortedImagePaths = List.from(imagePaths);
      }

      // 2. テキストのマージ (重複排除)
      List<String> lastPageTailLines = [];

      for (int i = 0; i < sortedOcrData.length; i++) {
        List<String> currentLines = _mergeLinesByCoordinate(sortedOcrData[i]);

        if (i == 0) {
          allLines.addAll(currentLines);
          int tailCount = (currentLines.length * 0.3).ceil();
          if (tailCount > 0) {
            lastPageTailLines = currentLines.sublist(max(0, currentLines.length - tailCount));
          }
        } else {
          for (var line in currentLines) {
            bool isDuplicate = false;
            for (var tailLine in lastPageTailLines) {
              if (_areSimilar(line, tailLine) || tailLine.contains(line) || line.contains(tailLine)) {
                isDuplicate = true;
                break;
              }
            }
            if (!isDuplicate) {
              allLines.add(line);
            }
          }
          int tailCount = (currentLines.length * 0.3).ceil();
          if (tailCount > 0) {
            lastPageTailLines = currentLines.sublist(max(0, currentLines.length - tailCount));
          }
        }
      }
    }

    String fullText = allLines.join('\n');
    bool isDiesel = fullText.contains('軽油');

    DateTime? date;
    int? amount;
    String storeName = '';
    String? tel;
    String? invoiceNum;

    final telKeywords = RegExp(r'(TEL|Tel|tel|電話|連絡先|☎|☏|📞|📱)');
    final excludeKeywords = RegExp(r'(登録|Invoice|No\.|Member|会員|ポイント)');
    final looseTelRegex = RegExp(r'[(]?[0OQ][0-9OQ\-\s)]{8,}[0-9OQ]');

    String? extractPhone(String line) {
      final match = looseTelRegex.firstMatch(line);
      if (match == null) return null;
      String candidate = match.group(0)!;
      String corrected = candidate.replaceAll(RegExp(r'[OQo]'), '0');
      String digits = corrected.replaceAll(RegExp(r'[^0-9]'), '');
      if ((digits.length == 10 || digits.length == 11) &&
          digits.startsWith('0') &&
          !digits.startsWith('00')) {
        if (corrected.contains('-')) {
          return corrected.replaceAll(RegExp(r'[^0-9\-]'), '');
        }
        return digits;
      }
      return null;
    }

    for (var line in allLines) {
      if (line.contains(RegExp(r'20\d{2}'))) continue;
      if (!line.contains(telKeywords)) continue;
      String? result = extractPhone(line);
      if (result != null) {
        tel = result;
        break;
      }
    }
    if (tel == null) {
      for (var line in allLines) {
        if (line.contains(RegExp(r'20\d{2}'))) continue;
        if (line.contains(telKeywords)) continue;
        if (line.contains(excludeKeywords)) continue;
        String? result = extractPhone(line);
        if (result != null) {
          tel = result;
          break;
        }
      }
    }

    final Map<String, String> ocrCorrectionMap = {
      'O': '0', 'D': '0', 'Q': '0', 'o': '0',
      'I': '1', 'l': '1', '|': '1',
      'Z': '2', 'z': '2',
      'S': '5', 's': '5',
      'B': '8', 'b': '8',
      'G': '6',
    };
    final invoiceKeywords = ['登録', '番号', 'No', 'Invoice', 'T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9'];

    for (var line in allLines) {
      bool hasKeyword = invoiceKeywords.any((k) => line.contains(k));
      bool looksLikeInvoice = RegExp(r'T[\s\-]?[0-9OQDBIZS]{5,}', caseSensitive: false).hasMatch(line);
      if (!hasKeyword && !looksLikeInvoice) continue;
      String norm = line.replaceAllMapped(RegExp(r'[０-９Ａ-Ｚａ-ｚ]'), (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0));
      final candidateRegex = RegExp(r'(T)?[\s\-]*([0-9OQDBIZSGl]{13})', caseSensitive: false);
      final match = candidateRegex.firstMatch(norm);
      if (match != null) {
        String rawNumberPart = match.group(2)!;
        String fixedNumber = rawNumberPart.split('').map((char) {
          return ocrCorrectionMap[char.toUpperCase()] ?? char;
        }).join('');
        if (RegExp(r'^\d{13}$').hasMatch(fixedNumber)) {
          invoiceNum = 'T$fixedNumber';
          break;
        }
      }
    }

    final dateRegex = RegExp(r'(20\d{2})[年/-]\s*(\d{1,2})[月/-]\s*(\d{1,2})日?');
    final timeRegex = RegExp(r'(\d{1,2}):(\d{2})');
    final timeKanjiRegex = RegExp(r'(\d{1,2})時(\d{1,2})分');

    for (var line in allLines) {
      final match = dateRegex.firstMatch(line);
      if (match != null) {
        try {
          int y = int.parse(match.group(1)!);
          int m = int.parse(match.group(2)!);
          int d = int.parse(match.group(3)!);
          int hour = 0;
          int minute = 0;
          var timeMatch = timeRegex.firstMatch(line);
          if (timeMatch == null) {
            timeMatch = timeKanjiRegex.firstMatch(line);
          }
          if (timeMatch != null) {
            hour = int.parse(timeMatch.group(1)!);
            minute = int.parse(timeMatch.group(2)!);
          }
          date = DateTime(y, m, d, hour, minute);
          break;
        } catch (_) {}
      }
    }

    int? anchorTax = _findAnchorTax(allLines);
    amount = _determineTotalAmount(allLines, anchorTax, isDiesel);

    int? target8;
    int? target10;
    int? tax8;
    int? tax10;

    if (isDiesel) {
      final dieselTargetPattern = RegExp(r'(10%|１０％).*?(対.|計|税抜|外税).*?([0-9,]+)');
      for (var line in allLines) {
        String norm = _normalizeAmountText(line);
        final match = dieselTargetPattern.firstMatch(norm);
        if (match != null) {
          List<int> vals = _extractValues(match.group(0)!);
          vals.removeWhere((v) => v == 10 || v == 8);
          if (vals.isNotEmpty) {
            vals.sort();
            int candidate = vals.last;
            if (amount != null && candidate > amount) continue;
            target10 = candidate;
            break;
          }
        }
      }
      if (target10 != null) {
        final dieselTaxPattern = RegExp(r'(10%|１０％).*?(税|Tax).*?([¥\\])?.*?([0-9,]+)');
        for (var line in allLines) {
          String norm = _normalizeAmountText(line);
          if (!norm.contains('10%') && !norm.contains('１０％')) continue;
          if (norm.contains('対象') || norm.contains('対縁')) continue;
          final match = dieselTaxPattern.firstMatch(norm);
          if (match != null) {
            List<int> vals = _extractValues(norm);
            vals.removeWhere((v) => v == 10 || v == 8);
            if (vals.isNotEmpty) {
              vals.sort();
              int candidateTax = vals.first;
              if ((target10 * 0.1 - candidateTax).abs() < target10 * 0.05) {
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
      List<int> candidates8 = [];
      List<int> candidates10 = [];
      final pattern8 = RegExp(r'(8%|８％|軽減|軽|8え|8X|8x).*?(対象|計|税抜|外税|課税).*?([0-9,]+)');
      final pattern10 = RegExp(r'(10%|１０％|標準).*?(対象|計|税抜|外税|課税).*?([0-9,]+)');
      final pattern8_B = RegExp(r'(内課税|課税).*?(8%|8え|8X|8x).*?([0-9,]+)');

      for (var line in allLines) {
        String norm = _normalizeAmountText(line);
        if (pattern8.hasMatch(norm)) {
          var vals = _extractValues(norm);
          vals.removeWhere((v) => v == 8 || v == 10);
          candidates8.addAll(vals);
        }
        if (pattern8_B.hasMatch(norm)) {
          var vals = _extractValues(norm);
          vals.removeWhere((v) => v == 8 || v == 10);
          candidates8.addAll(vals);
        }
        if (pattern10.hasMatch(norm)) {
          var vals = _extractValues(norm);
          vals.removeWhere((v) => v == 10 || v == 8);
          candidates10.addAll(vals);
        }
      }
      if (amount != null) {
        bool resolved = false;
        if (!resolved && candidates8.contains(amount)) {
          target8 = amount; target10 = 0; resolved = true;
        } else if (!resolved && candidates10.contains(amount)) {
          target10 = amount; target8 = 0; resolved = true;
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
        }
      }
      if (target8 != null && target8 > 0) tax8 = (target8 * 8 / 108).floor();
      if (target10 != null && target10 > 0) tax10 = (target10 * 10 / 110).floor();
    }

    for (int i = 0; i < allLines.length && i < 5; i++) {
      String l = allLines[i].trim();
      if (l.isEmpty) continue;
      if (l.contains('レシート') || l.contains('領収') || looseTelRegex.hasMatch(l) || dateRegex.hasMatch(l)) continue;
      if (RegExp(r'^[\d\s¥,.\-*]+$').hasMatch(l)) continue;
      storeName = l;
      break;
    }

    print('[DEBUG] ========== 解析終了 ==========');

    return ReceiptData(
      id: _uuid.v4(),
      date: date,
      storeName: storeName,
      amount: amount,
      invoiceNumber: invoiceNum,
      tel: tel,
      taxAmount10: tax10,
      targetAmount10: target10,
      taxAmount8: tax8,
      targetAmount8: target8,
      ocrData: sortedOcrData.first,
      sourceOcrData: sortedOcrData,
      sourceImagePaths: sortedImagePaths,
      rawText: fullText,
    );
  }
}