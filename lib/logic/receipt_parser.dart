// lib/logic/receipt_parser.dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:uuid/uuid.dart';
import '../models/receipt_data.dart';
import 'parser/receipt_ocr_merger.dart';
import 'parser/extractors/basic_info_extractor.dart';
import 'parser/extractors/amount_extractor.dart';
import 'parser/extractors/tax_extractor.dart';

class ReceiptParser {
  final _uuid = const Uuid();

  /// 【修正】リスト対応版 parse メソッド
  /// 各モジュールに処理を委譲してReceiptDataを生成するファサード
  ReceiptData parse(List<RecognizedText> recognizedTexts, List<String> imagePaths) {
    // 1. OCR結果の結合・整列処理
    final mergeResult = ReceiptOcrMerger.process(recognizedTexts, imagePaths);
    final allLines = mergeResult.allLines;

    // 2. 基本情報抽出 (日付, 店名, TEL, インボイス)
    final basicInfo = BasicInfoExtractor.extract(allLines);

    // 3. 軽油判定
    final fullText = allLines.join('\n');
    final isDiesel = fullText.contains('軽油');

    // 4. 税額アンカー探索 (合計金額特定のヒント)
    final anchorTax = TaxExtractor.findAnchorTax(allLines);

    // 5. 合計金額の決定
    final amount = AmountExtractor.extract(allLines, anchorTax, isDiesel);

    // 6. 税額詳細計算 (10%, 8% の内訳)
    // 合計金額が特定できなかった場合は0として扱う
    final taxResult = TaxExtractor.extract(allLines, amount ?? 0, isDiesel);

    // 7. ReceiptDataの生成
    return ReceiptData(
      id: _uuid.v4(),
      date: basicInfo.date,
      storeName: basicInfo.storeName,
      amount: amount,
      invoiceNumber: basicInfo.invoiceNum,
      tel: basicInfo.tel,
      taxAmount10: taxResult.tax10,
      targetAmount10: taxResult.target10,
      taxAmount8: taxResult.tax8,
      targetAmount8: taxResult.target8,
      ocrData: mergeResult.sortedOcrData.first,
      sourceOcrData: mergeResult.sortedOcrData,
      sourceImagePaths: mergeResult.sortedImagePaths,
      rawText: fullText,
    );
  }
}