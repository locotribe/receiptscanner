// lib/logic/parser/receipt_ocr_merger.dart
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'receipt_text_util.dart';

/// 結合処理の結果を保持するクラス
class OcrMergeResult {
  final List<String> allLines;
  final List<RecognizedText> sortedOcrData;
  final List<String> sortedImagePaths;

  OcrMergeResult(this.allLines, this.sortedOcrData, this.sortedImagePaths);
}

class ReceiptOcrMerger {
  /// OCR結果と画像パスを受け取り、結合・整列処理を行う
  static OcrMergeResult process(List<RecognizedText> recognizedTexts, List<String> imagePaths) {
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
              if (ReceiptTextUtil.areSimilar(line, tailLine) || tailLine.contains(line) || line.contains(tailLine)) {
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

    return OcrMergeResult(allLines, sortedOcrData, sortedImagePaths);
  }

  /// 座標情報を使って、同じ高さにあるテキストを1行に結合する
  /// (複数画像のマージ時のみ使用)
  static List<String> _mergeLinesByCoordinate(RecognizedText recognizedText) {
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
  static int _calculateOverlapScore(RecognizedText textA, RecognizedText textB) {
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
          if (ReceiptTextUtil.areSimilar(strA, strB)) {
            score += 5;
          }
        }
      }
    }
    return score;
  }
}