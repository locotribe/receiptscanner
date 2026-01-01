import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:uuid/uuid.dart';
import '../models/receipt_data.dart';

class ReceiptParser {
  final _uuid = const Uuid();

  /// 座標情報を使って、同じ高さにあるテキストを1行に結合する
  /// 改良版: Y座標でグループ化した後、必ずX座標(左)順に並べる
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
    // レシートの行間隔によるが、文字の高さの半分くらいズレてても同じ行とみなす
    for (var line in allLines) {
      bool added = false;
      double lineHeight = line.boundingBox.height;
      double lineCenterY = line.boundingBox.center.dy;

      // 既存の行グループの中に、高さが近いものがあるか探す
      for (var row in rows) {
        if (row.isEmpty) continue;

        // その行の平均的なY座標と比較
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
      // 左から右へソート (これで「金額 商品名」の逆転を防ぐ)
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));

      // テキスト結合
      String mergedText = row.map((e) => e.text).join(' ');
      mergedLines.add(mergedText);
    }

    return mergedLines;
  }

  /// 金額解析用の文字クリーニング
  /// OCR特有の誤読パターンを修正する
  String _normalizeAmountText(String text) {
    String s = text;
    // 全角数字を半角に
    s = s.replaceAllMapped(RegExp(r'[０-９]'), (m) => (m.group(0)!.codeUnitAt(0) - 0xFEE0).toString());

    // カンマ、円マークの揺れを修正
    // "4"や"Y"が数字の直前にあれば"¥"の誤読の可能性が高い (例: 42,000 -> ¥2,000)
    // ただし "4" 単体や "No.4" などを巻き込まないよう、後ろにカンマや3桁以上の数字がある場合などを狙う
    s = s.replaceAll(RegExp(r'[Yy]\s*(?=[0-9])'), '¥'); // Y2000 -> ¥2000
    s = s.replaceAll(RegExp(r'(?<![0-9])4(?=[0-9]{1,3}(,|¥d{3}))'), '¥'); // 数字の前ではない4 -> ¥ (42,000 -> ¥2,000)

    // 紛らわしい記号を削除または置換
    s = s.replaceAll(RegExp(r'[\$\*＊]'), ''); // $や*はノイズとして消す
    s = s.replaceAll('l', '1'); // l -> 1
    s = s.replaceAll('O', '0'); // O -> 0

    return s;
  }

  ReceiptData parse(RecognizedText recognizedText) {
    // 1. 改良された行結合ロジックを実行
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
    // 年月日の間にスペースが入るケースに対応
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

    // --- 金額解析 (改良版) ---
    int foundAmount = 0;

    // 金額判定の優先順位:
    // 1. 「合計」などのキーワードがあり、かつ「¥」マークがある数値
    // 2. 「合計」などのキーワードがある行の、末尾にある数値
    // 3. 全文の中で「¥」マークがついている最大数値

    final totalKeywords = ['合計', '小計', 'お買上', '支払', '合　計', 'お釣り', '楽天', 'Pay'];
    final amountPattern = RegExp(r'[¥\\]?([0-9]{1,3}(,[0-9]{3})*)'); // 1,000 or ¥1000

    // スキャンループ
    for (var line in lines) {
      // ノイズ除去・正規化
      String normalizedLine = _normalizeAmountText(line);

      // "7点" のような数量を金額と間違えないためのガード
      // 数字の直後に "点" "個" "NO" "No" がある場合はその数字をマスクする
      normalizedLine = normalizedLine.replaceAll(RegExp(r'\d+\s*[点個]|No\.?\s*\d+'), '');

      bool isTotalLine = totalKeywords.any((k) => line.contains(k));

      // 行内の数値をすべて抽出
      final matches = amountPattern.allMatches(normalizedLine);

      for (var m in matches) {
        String valStr = m.group(1)!.replaceAll(',', '');
        int val = int.tryParse(valStr) ?? 0;

        if (val == 0) continue;
        if (val > 10000000) continue; // 異常値除外
        if (val < 10 && !normalizedLine.contains('¥')) continue; // ¥マークなしの1桁数字はゴミの可能性大

        // キーワード行の数値を最優先
        if (isTotalLine) {
          // 既存の候補より大きければ採用、ただし日付(2025)っぽいものは、
          // 本当に金額記号がついている場合のみ許可するなどの判定が理想
          // ここでは単純に最大値を更新
          if (val > foundAmount) {
            foundAmount = val;
          }
        }
      }
    }

    // キーワードで見つからなかった場合、"¥"がついている最大値を探す（バックアップ）
    if (foundAmount == 0) {
      for (var line in lines) {
        if (line.toLowerCase().contains('no') || line.contains('ID') || telRegex.hasMatch(line)) continue;

        String normalizedLine = _normalizeAmountText(line);
        if (normalizedLine.contains('¥')) {
          final matches = RegExp(r'\d+').allMatches(normalizedLine.replaceAll(',', '').replaceAll('¥', ''));
          for (var m in matches) {
            int val = int.tryParse(m.group(0)!) ?? 0;
            if (val > foundAmount && val < 10000000) foundAmount = val;
          }
        }
      }
    }

    // それでもダメなら単純最大値 (ただし日付2025などを避けるため、ある程度大きい数値を優先)
    if (foundAmount == 0) {
      for (var line in lines) {
        if (line.toLowerCase().contains('no') || line.contains('ID')) continue;
        String normalizedLine = _normalizeAmountText(line);
        final matches = RegExp(r'\d+').allMatches(normalizedLine.replaceAll(',', ''));
        for (var m in matches) {
          int val = int.tryParse(m.group(0)!) ?? 0;
          // 誤検出防止: 100円未満の数字単体は無視、日付(2000-2100)周辺も怪しいが、
          // ここでは「現在見つかっている最大値より大きければ」で更新
          if (val > foundAmount && val < 10000000) foundAmount = val;
        }
      }
    }

    if (foundAmount > 0) amount = foundAmount;

    // --- 店名解析 ---
    for (int i = 0; i < lines.length && i < 5; i++) {
      String l = lines[i].trim();
      if (l.isEmpty) continue;

      if (l.contains('レシート')) continue;
      if (l.contains('領収')) continue;
      if (telRegex.hasMatch(l)) continue;
      if (dateRegex.hasMatch(l)) continue;

      // 数字だけの行や、記号だけの行を除外
      if (RegExp(r'^[\d\s¥,.\-*]+$').hasMatch(l)) continue;

      storeName = l;
      break;
    }

    // 税額の簡易計算
    int? tax10;
    int? target10;
    if (amount != null) {
      tax10 = (amount * 10 / 110).floor();
      target10 = amount - tax10;
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
      ocrData: recognizedText,
      rawText: fullText,
    );
  }
}