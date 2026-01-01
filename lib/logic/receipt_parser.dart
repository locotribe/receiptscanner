// lib/logic/receipt_parser.dart
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:uuid/uuid.dart';
import '../models/receipt_data.dart';

class ReceiptParser {
  final _uuid = const Uuid();

  /// 座標情報を使って、同じ高さにあるテキストを1行に結合する
  List<String> _mergeLinesByCoordinate(RecognizedText recognizedText) {
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
    }

    return mergedLines;
  }

  /// 金額解析用の文字クリーニング
  String _normalizeAmountText(String text) {
    String s = text;
    // 全角数字を半角に
    s = s.replaceAllMapped(RegExp(r'[０-９]'), (m) => (m.group(0)!.codeUnitAt(0) - 0xFEE0).toString());

    // カンマ、円マークの揺れを修正
    s = s.replaceAll(RegExp(r'[Yy]\s*(?=[0-9])'), '¥');
    s = s.replaceAll(RegExp(r'(?<![0-9])4(?=[0-9]{1,3}(,|¥d{3}))'), '¥');

    // 紛らわしい記号を削除または置換
    s = s.replaceAll(RegExp(r'[\$\*＊]'), '');
    s = s.replaceAll('l', '1');
    s = s.replaceAll('O', '0');

    // 数字の間のスペースを除去 ("4 050" -> "4050")
    s = s.replaceAllMapped(RegExp(r'(\d)\s+([0-9])'), (Match m) {
      return '${m.group(1)}${m.group(2)}';
    });

    return s;
  }

  /// 文字列から数値を抽出するヘルパー
  List<int> _extractValues(String text) {
    List<int> values = [];
    final matches = RegExp(r'[0-9]{1,3}(,[0-9]{3})*').allMatches(text);
    for (var m in matches) {
      String valStr = m.group(0)!.replaceAll(',', '');
      int? val = int.tryParse(valStr);
      if (val != null) values.add(val);
    }
    return values;
  }

  ReceiptData parse(RecognizedText recognizedText) {
    List<String> lines = _mergeLinesByCoordinate(recognizedText);
    String fullText = lines.join('\n');

    DateTime? date;
    int? amount;
    String storeName = '';
    String? tel;
    String? invoiceNum;

    // --- 電話番号解析 ---
    final telRegex = RegExp(r'0\d{1,4}-\d{1,4}-\d{3,4}');
    for (var line in lines) {
      String cleanLine = line.replaceAll(RegExp(r'\s+'), '');
      final match = telRegex.firstMatch(cleanLine);
      if (match != null) {
        tel = match.group(0);
        break;
      }
    }

    // --- インボイス番号 (T + 13桁) ---
    final invoiceRegex = RegExp(r'T\d{13}');
    for (var line in lines) {
      String cleanLine = line.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final match = invoiceRegex.firstMatch(cleanLine);
      if (match != null) {
        invoiceNum = match.group(0);
        break;
      }
    }

    // --- 日付解析 ---
    final dateRegex = RegExp(r'(20\d{2})[年/-]\s*(\d{1,2})[月/-]\s*(\d{1,2})日?');
    for (var line in lines) {
      final match = dateRegex.firstMatch(line);
      if (match != null) {
        try {
          int y = int.parse(match.group(1)!);
          int m = int.parse(match.group(2)!);
          int d = int.parse(match.group(3)!);

          int hour = 0;
          int minute = 0;
          final timeRegex = RegExp(r'(\d{1,2}):(\d{2})');
          final timeMatch = timeRegex.firstMatch(line);
          if (timeMatch != null) {
            hour = int.parse(timeMatch.group(1)!);
            minute = int.parse(timeMatch.group(2)!);
          }

          date = DateTime(y, m, d, hour, minute);
          break;
        } catch (e) {
          print('Date parse error: $e');
        }
      }
    }

    // --- 金額解析 ---
    int foundAmount = 0;
    final totalKeywords = ['合計', '小計', 'お買上', '支払', '合　計', 'お釣り', '楽天', 'Pay'];
    final amountPattern = RegExp(r'[¥\\]?([0-9]{1,3}(,[0-9]{3})*)');

    for (var line in lines) {
      String normalizedLine = _normalizeAmountText(line);
      normalizedLine = normalizedLine.replaceAll(RegExp(r'\d+\s*[点個]|No\.?\s*\d+'), '');

      bool isTotalLine = totalKeywords.any((k) => line.contains(k));
      final matches = amountPattern.allMatches(normalizedLine);

      for (var m in matches) {
        String valStr = m.group(1)!.replaceAll(',', '');
        int val = int.tryParse(valStr) ?? 0;

        if (val == 0) continue;
        if (val > 10000000) continue;
        if (val < 10 && !normalizedLine.contains('¥')) continue;

        if (isTotalLine) {
          if (val > foundAmount) {
            foundAmount = val;
          }
        }
      }
    }

    // バックアップ: キーワードなし
    if (foundAmount == 0) {
      for (var line in lines) {
        if (line.toLowerCase().contains('no') || line.contains('ID') || telRegex.hasMatch(line)) continue;
        String normalizedLine = _normalizeAmountText(line);
        final matches = RegExp(r'\d+').allMatches(normalizedLine.replaceAll(',', '').replaceAll('¥', ''));
        for (var m in matches) {
          int val = int.tryParse(m.group(0)!) ?? 0;
          if (val > foundAmount && val < 10000000) foundAmount = val;
        }
      }
    }

    if (foundAmount > 0) amount = foundAmount;

    // --- 税率別対象額の解析 (新ロジック) ---
    // 候補値をすべてリストアップする
    List<int> candidates8 = [];
    List<int> candidates10 = [];

    // 「対象」「計」「税抜」「外税」などのキーワードがある行から数値を拾う
    final pattern8 = RegExp(r'(8%|８％|軽減|軽).*?(対象|計|税抜|外税).*?([0-9,]+)');
    final pattern10 = RegExp(r'(10%|１０％|標準).*?(対象|計|税抜|外税).*?([0-9,]+)');

    for (var line in lines) {
      String norm = _normalizeAmountText(line);

      if (pattern8.hasMatch(norm)) {
        candidates8.addAll(_extractValues(norm));
      }
      if (pattern10.hasMatch(norm)) {
        candidates10.addAll(_extractValues(norm));
      }
    }

    int? target8;
    int? target10;

    // --- 整合性判定ロジック ---
    if (amount != null) {
      bool resolved = false;

      // 1. 合計金額との完全一致チェック (税込表記) -> 最優先
      if (!resolved) {
        if (candidates8.contains(amount)) {
          target8 = amount;
          target10 = 0;
          resolved = true;
        } else if (candidates10.contains(amount)) {
          target10 = amount;
          target8 = 0;
          resolved = true;
        }
      }

      // 2. 外税(税抜)からの逆算チェック
      if (!resolved) {
        // 8%候補の中に、消費税を足すと合計金額になるものがあるか？
        for (var val in candidates8) {
          int tax = (val * 0.08).floor();
          // 計算誤差±1円を許容
          if ((val + tax - amount).abs() <= 1) {
            target8 = amount; // アプリ上は税込(合計)額をセット
            target10 = 0;
            resolved = true;
            break;
          }
        }
      }
      if (!resolved) {
        // 10%候補の逆算チェック
        for (var val in candidates10) {
          int tax = (val * 0.10).floor();
          if ((val + tax - amount).abs() <= 1) {
            target10 = amount;
            target8 = 0;
            resolved = true;
            break;
          }
        }
      }

      // 3. 混合税率の足し算チェック
      if (!resolved && candidates8.isNotEmpty && candidates10.isNotEmpty) {
        for (var v8 in candidates8) {
          for (var v10 in candidates10) {
            if (v8 + v10 == amount) {
              target8 = v8;
              target10 = v10;
              resolved = true;
              break;
            }
          }
          if (resolved) break;
        }
      }

      // 4. フォールバック (読み取れなかった場合)
      if (!resolved) {
        // 変に分割されるよりは、全額10%としておく方が修正が楽
        target10 = amount;
        target8 = 0;
      }
    }

    // --- 税額の自動計算 (内税) ---
    // ここではOCRの読み取り値は使わず、確定した対象額から常に逆算する
    int? tax8;
    int? tax10;

    if (target8 != null && target8 > 0) {
      tax8 = (target8 * 8 / 108).floor();
    }
    if (target10 != null && target10 > 0) {
      tax10 = (target10 * 10 / 110).floor();
    }

    // --- 店名解析 ---
    for (int i = 0; i < lines.length && i < 5; i++) {
      String l = lines[i].trim();
      if (l.isEmpty) continue;
      if (l.contains('レシート') || l.contains('領収') || telRegex.hasMatch(l) || dateRegex.hasMatch(l)) continue;
      if (RegExp(r'^[\d\s¥,.\-*]+$').hasMatch(l)) continue;
      storeName = l;
      break;
    }

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