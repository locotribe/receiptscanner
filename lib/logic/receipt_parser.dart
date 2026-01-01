// lib/logic/receipt_parser.dart
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:uuid/uuid.dart';
import '../models/receipt_data.dart';

class ReceiptParser {
  final _uuid = const Uuid();

  /// 座標情報を使って、同じ高さにあるテキストを1行に結合する
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
      print('[DEBUG] Row: $mergedText');
    }
    print('[DEBUG] --- 行結合処理終了 (${mergedLines.length}行) ---');

    return mergedLines;
  }

  /// 金額解析用の文字クリーニング
  String _normalizeAmountText(String text) {
    String s = text;
    // 全角数字を半角に
    s = s.replaceAllMapped(RegExp(r'[０-９]'), (m) => (m.group(0)!.codeUnitAt(0) - 0xFEE0).toString());

    // カンマの後のスペースを除去 ("6, 440" -> "6,440")
    s = s.replaceAll(RegExp(r',\s+'), ',');

    // カンマ、円マークの揺れを修正
    s = s.replaceAll(RegExp(r'[Yy]\s*(?=[0-9])'), '¥');

    // Wも円マークの誤認識として処理 (例: W76 -> ¥76)
    s = s.replaceAll(RegExp(r'[Ww]\s*(?=[0-9])'), '¥');

    // 4と¥の誤認修正: 数字の前にある4を¥に (例: 46,440 -> ¥6,440)
    // 条件: 前に数字がなく、後ろに「数字1-3桁＋カンマ」または「数字3桁」が続く場合
    s = s.replaceAll(RegExp(r'(?<![0-9])4(?=[0-9]{1,3}(,|¥d{3}))'), '¥');

    // 紛らわしい記号を削除または置換
    s = s.replaceAll(RegExp(r'[\$\*＊]'), '');
    s = s.replaceAll('l', '1');
    s = s.replaceAll('O', '0');

    // 数字の間のスペースを除去 ("4 050" -> "4050")
    s = s.replaceAllMapped(RegExp(r'(\d)\s+([0-9])'), (Match m) {
      return '${m.group(1)}${m.group(2)}';
    });

    // 単位（点、個）がついている数字を事前にマスクする
    // "合計1点" の "1" を拾わないようにするため
    s = s.replaceAll(RegExp(r'\d+\s*[点個]'), '');

    return s;
  }

  /// 文字列から数値を抽出するヘルパー
  /// 「ゴーストナンバー処理」を含む
  /// OCRが「¥」を「4」と誤認して「41026」となった場合、「1026」も候補として生成する
  List<int> _extractValues(String text) {
    List<int> values = [];
    // 単純に [数字とカンマの塊] をすべて抽出する
    final matches = RegExp(r'[0-9,]+').allMatches(text);

    for (var m in matches) {
      String valStr = m.group(0)!.replaceAll(',', '');
      if (valStr.isEmpty) continue;

      int? val = int.tryParse(valStr);
      if (val != null) {
        values.add(val);

        // --- ゴーストナンバー処理 (4剥がし) ---
        // 【重要】3桁以上で、先頭が '4' の場合 (例: 41026->1026, 476->76)
        // 税額(76円)が476と誤認されるケースに対応するため、条件を4桁から3桁へ緩和
        if (valStr.length >= 3 && valStr.startsWith('4')) {
          String strippedStr = valStr.substring(1); // 先頭の4を除去
          int? strippedVal = int.tryParse(strippedStr);
          if (strippedVal != null && strippedVal > 0) {
            // 剥がした結果も候補に追加
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
      bool hasKeyword = taxKeywords.any((k) => norm.contains(k));

      if (hasKeyword) {
        // 対象額の誤検出を防ぐ
        if (norm.contains('対象') || norm.contains('対縁')) {
          print('[DEBUG] SKIP(対象額の可能性): "$line"');
          continue;
        }

        // 「10%」や「8%」を数値として拾わないように事前に削除
        String textForExtraction = norm.replaceAll(RegExp(r'[0-9０-９]+[%％]'), '');

        List<int> vals = _extractValues(textForExtraction);
        for (var val in vals) {
          if (val > 0 && val < 50000) {
            print('[DEBUG] 税額候補発見: $val (由来: "$line")');
            if (bestTax == null || (val < bestTax)) {
              bestTax = val;
              print('[DEBUG] -> 暫定採用 (より小さい値を優先)');
            } else {
              print('[DEBUG] -> 棄却 (現在のベスト $bestTax より大きい)');
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

      if (excludeKeywords.any((k) => line.contains(k))) {
        print('[DEBUG] 除外ワード検知: "$line" -> スキップ');
        continue;
      }

      bool isTotalLine = totalKeywords.any((k) => line.contains(k));
      bool hasYenMark = norm.contains('¥') || norm.contains('\\');

      // 1. ¥マーク付き (ゴーストナンバー処理を含む)
      final yenMatches = amountPattern.allMatches(norm);
      for (var m in yenMatches) {
        String rawNumPart = m.group(2)!;
        List<int> extractedVals = _extractValues(rawNumPart);

        for (var val in extractedVals) {
          if (val == 0) continue;
          int score = 20;
          if (isTotalLine) score += 50;
          if (hasYenMark) score += 20;

          scores[val] = (scores[val] ?? 0) + score;
          print('[DEBUG] 候補追加(¥付): $val (Score: $score, Line: "$line")');
        }
      }

      // 2. キーワード行
      if (isTotalLine) {
        final plainMatches = plainNumberPattern.allMatches(norm.replaceAll('¥', ''));
        for (var m in plainMatches) {
          List<int> extractedVals = _extractValues(m.group(1)!);
          for (var val in extractedVals) {
            if (val == 0) continue;
            scores[val] = (scores[val] ?? 0) + 30;
            print('[DEBUG] 候補追加(Key行): $val (Score: ${scores[val]}, Line: "$line")');
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

    // --- 整合性チェックとフィルタリング ---
    int? bestAmount;
    int maxScore = -1;

    print('[DEBUG] --- 候補の整合性チェック開始 ---');
    scores.forEach((amount, score) {
      if (amount > 10000000) return;

      print('[DEBUG] 検査対象: ¥$amount (Score: $score)');

      if (anchorTax != null && anchorTax > 0) {
        double estimatedTax = amount * 0.10;
        double estimatedTax8 = amount * 0.08;

        // 【重要】通常レシートの許容誤差を 5% から 2% (+5円) に厳格化
        double tolerance = isDiesel ? (amount * 0.05 + 500) : (amount * 0.02 + 5);

        // 内税計算での検証
        double estimatedInnerTax8 = amount * 8 / 108;
        double estimatedInnerTax10 = amount * 10 / 110;

        bool isConsistent = false;

        if ((estimatedTax - anchorTax).abs() < tolerance ||
            (estimatedTax8 - anchorTax).abs() < tolerance ||
            (estimatedInnerTax8 - anchorTax).abs() < 5 || // 内税厳密チェック
            (estimatedInnerTax10 - anchorTax).abs() < 5
        ) {
          isConsistent = true;
          print('[DEBUG]  -> 税額計算OK: 実税=$anchorTax');
        } else {
          print('[DEBUG]  -> 税額計算NG: 実税=$anchorTax vs 予想(8%内)=$estimatedInnerTax8');
        }

        if (isDiesel) {
          if (amount > anchorTax * 5) {
            isConsistent = true;
            print('[DEBUG]  -> 軽油特例OK: 金額が税額の5倍以上');
          } else {
            isConsistent = false;
            print('[DEBUG]  -> 軽油特例NG: 金額が小さすぎる');
          }
        } else {
          if (estimatedTax > anchorTax * 3 && !isConsistent) {
            isConsistent = false;
            print('[DEBUG]  -> 通常NG: 予想税額が実税額より大きすぎる');
          }
        }

        if (!isConsistent) {
          print('[DEBUG]  -> 最終判定: 不合格 (Skip)');
          return;
        }
      } else {
        print('[DEBUG]  -> アンカー税額なしのためチェックskip');
      }

      if (score > maxScore) {
        maxScore = score;
        bestAmount = amount;
        print('[DEBUG]  -> 暫定ベスト更新: ¥$bestAmount (Score: $maxScore)');
      } else if (score == maxScore) {
        if (bestAmount != null && amount > bestAmount!) {
          bestAmount = amount;
          print('[DEBUG]  -> 同点のため大きい方を採用: ¥$bestAmount');
        }
      }
    });

    print('[DEBUG] 合計金額決定: $bestAmount');
    return bestAmount;
  }

  ReceiptData parse(RecognizedText recognizedText) {
    print('[DEBUG] ========== 解析開始 (Debug Mode) ==========');
    List<String> lines = _mergeLinesByCoordinate(recognizedText);
    String fullText = lines.join('\n');
    bool isDiesel = fullText.contains('軽油');
    print('[DEBUG] 軽油フラグ: $isDiesel');

    DateTime? date;
    int? amount;
    String storeName = '';
    String? tel;
    String? invoiceNum;

    // --- 電話番号解析 (修正版: 揺れ吸収ロジック追加) ---
    // 従来の telRegex はハイフン必須だったが、緩い条件で探索する
    final looseTelRegex = RegExp(r'[(]?[0O][0-9O\-\s)]{8,}[0-9O]');
    for (var line in lines) {
      if (line.contains(RegExp(r'20\d{2}'))) continue; // 日付誤検知防止

      final match = looseTelRegex.firstMatch(line);
      if (match != null) {
        String candidate = match.group(0)!;
        // クリーニング: O→0, 数字以外削除
        String digits = candidate.replaceAll(RegExp(r'[O]'), '0').replaceAll(RegExp(r'[^0-9]'), '');

        // 日本の電話番号は10桁(固定)か11桁(携帯・IP)、かつ先頭は0
        if ((digits.length == 10 || digits.length == 11) && digits.startsWith('0')) {
          tel = digits;
          print('[DEBUG] 電話番号検出(補正済): $tel (元: "$candidate")');
          break;
        }
      }
    }

    // --- インボイス番号 (修正版: 揺れ吸収ロジック追加) ---
    // 【修正】文字揺れ（B→8, S→5など）や「登録番号」キーワードからの推測に対応
    final Map<String, String> ocrCorrectionMap = {
      'O': '0', 'D': '0', 'Q': '0', 'o': '0',
      'I': '1', 'l': '1', '|': '1',
      'Z': '2', 'z': '2',
      'S': '5', 's': '5',
      'B': '8', 'b': '8',
      'G': '6',
    };
    final invoiceKeywords = ['登録', '番号', 'No', 'Invoice', 'T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9'];

    for (var line in lines) {
      // キーワード判定: 行内にキーワードがあるか、または T+数字っぽいものがあるか
      bool hasKeyword = invoiceKeywords.any((k) => line.contains(k));
      // Tの後に数字(や誤読文字)が5桁以上続くか？ (緩い判定)
      bool looksLikeInvoice = RegExp(r'T[\s\-]?[0-9OQDBIZS]{5,}', caseSensitive: false).hasMatch(line);

      if (!hasKeyword && !looksLikeInvoice) continue;

      // 正規化: 全角英数を半角に変換（簡易正規化）
      String norm = line.replaceAllMapped(RegExp(r'[０-９Ａ-Ｚａ-ｚ]'), (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0));

      // 抽出用正規表現: (T)? + (スペース|ハイフン)* + (数字|誤読文字){13}
      // Tはあってもなくても良いが、数字部分は13桁
      final candidateRegex = RegExp(r'(T)?[\s\-]*([0-9OQDBIZSGl]{13})', caseSensitive: false);
      final match = candidateRegex.firstMatch(norm);

      if (match != null) {
        String rawNumberPart = match.group(2)!;

        // マップを使って数字に復元
        String fixedNumber = rawNumberPart.split('').map((char) {
          return ocrCorrectionMap[char.toUpperCase()] ?? char;
        }).join('');

        // 最終確認: 数字13桁か
        if (RegExp(r'^\d{13}$').hasMatch(fixedNumber)) {
          invoiceNum = 'T$fixedNumber';
          // ログフォーマットは既存に合わせる
          print('[DEBUG] インボイス検出(補正済): $invoiceNum (元: "${match.group(0)}")');
          break;
        }
      }
    }

    // --- 日付解析 (日本語表記対応済) ---
    final dateRegex = RegExp(r'(20\d{2})[年/-]\s*(\d{1,2})[月/-]\s*(\d{1,2})日?');
    final timeRegex = RegExp(r'(\d{1,2}):(\d{2})');
    final timeKanjiRegex = RegExp(r'(\d{1,2})時(\d{1,2})分');

    for (var line in lines) {
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
          print('[DEBUG] 日付・時刻検出: $date');
          break;
        } catch (_) {}
      }
    }

    // --- 金額解析 ---
    int? anchorTax = _findAnchorTax(lines);
    amount = _determineTotalAmount(lines, anchorTax, isDiesel);

    // --- 税率別対象額の解析 ---
    int? target8;
    int? target10;
    int? tax8;
    int? tax10;

    print('[DEBUG] --- 内訳解析開始 ---');

    if (isDiesel) {
      print('[DEBUG] 軽油特例ルートで内訳を探索します');
      final dieselTargetPattern = RegExp(r'(10%|１０％).*?(対.|計|税抜|外税).*?([0-9,]+)');

      for (var line in lines) {
        String norm = _normalizeAmountText(line);
        final match = dieselTargetPattern.firstMatch(norm);
        if (match != null) {
          print('[DEBUG] 軽油対象額候補行: "$line" -> Norm: "$norm"');
          List<int> vals = _extractValues(match.group(0)!);
          vals.removeWhere((v) => v == 10 || v == 8);
          print('[DEBUG]  -> 抽出数値: $vals');

          if (vals.isNotEmpty) {
            vals.sort();
            int candidate = vals.last;
            if (amount != null && candidate > amount) {
              print('[DEBUG]  -> 棄却: 合計金額($amount)より大きい');
              continue;
            }
            target10 = candidate;
            print('[DEBUG]  -> 10%対象額として採用: $target10');
            break;
          }
        }
      }

      if (target10 != null) {
        final dieselTaxPattern = RegExp(r'(10%|１０％).*?(税|Tax).*?([¥\\])?.*?([0-9,]+)');
        for (var line in lines) {
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
      print('[DEBUG] 通常ルートで内訳を探索します');
      List<int> candidates8 = [];
      List<int> candidates10 = [];

      final pattern8 = RegExp(r'(8%|８％|軽減|軽|8え|8X|8x).*?(対象|計|税抜|外税|課税).*?([0-9,]+)');
      final pattern10 = RegExp(r'(10%|１０％|標準).*?(対象|計|税抜|外税|課税).*?([0-9,]+)');
      final pattern8_B = RegExp(r'(内課税|課税).*?(8%|8え|8X|8x).*?([0-9,]+)');

      for (var line in lines) {
        String norm = _normalizeAmountText(line);

        bool matched8 = false;
        if (pattern8.hasMatch(norm)) {
          var vals = _extractValues(norm);
          vals.removeWhere((v) => v == 8 || v == 10);
          candidates8.addAll(vals);
          matched8 = true;
          print('[DEBUG] 8%候補発見(A): $vals (Line: "$line")');
        }
        if (!matched8 && pattern8_B.hasMatch(norm)) {
          var vals = _extractValues(norm);
          vals.removeWhere((v) => v == 8 || v == 10);
          candidates8.addAll(vals);
          print('[DEBUG] 8%候補発見(B): $vals (Line: "$line")');
        }

        if (pattern10.hasMatch(norm)) {
          var vals = _extractValues(norm);
          vals.removeWhere((v) => v == 10 || v == 8);
          candidates10.addAll(vals);
          print('[DEBUG] 10%候補発見: $vals (Line: "$line")');
        }
      }

      if (amount != null) {
        bool resolved = false;
        if (!resolved && candidates8.contains(amount)) {
          target8 = amount; target10 = 0; resolved = true;
          print('[DEBUG] 内訳一致(8%): 全額対象');
        } else if (!resolved && candidates10.contains(amount)) {
          target10 = amount; target8 = 0; resolved = true;
          print('[DEBUG] 内訳一致(10%): 全額対象');
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

    // --- 店名解析 ---
    for (int i = 0; i < lines.length && i < 5; i++) {
      String l = lines[i].trim();
      if (l.isEmpty) continue;
      // 【修正済】telRegex -> looseTelRegex を使用
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
      ocrData: recognizedText,
      rawText: fullText,
    );
  }
}