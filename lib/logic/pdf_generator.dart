// lib/logic/pdf_generator.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:printing/printing.dart';

class PdfGenerator {

  /// 画像リストとOCR結果リストから、マルチページ対応のスキャナー品質検索可能PDFを生成する
  /// (不可視テキストレイヤー方式)
  Future<Uint8List> generateSearchablePdf(List<String> imagePaths, List<RecognizedText> recognizedTexts) async {
    final pdf = pw.Document();

    // 2. 日本語フォントのロード
    final font = await PdfGoogleFonts.notoSansJPRegular();

    // リストの要素数が一致しない場合の安全策として、少ない方の数に合わせる
    final count = imagePaths.length < recognizedTexts.length ? imagePaths.length : recognizedTexts.length;

    for (int i = 0; i < count; i++) {
      final imagePath = imagePaths[i];
      final recognizedText = recognizedTexts[i];

      // 1. 画像の読み込み
      final imageFile = File(imagePath);
      if (!imageFile.existsSync()) continue;

      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) continue; // 画像読み込み失敗時はスキップ

      final pdfImage = pw.MemoryImage(imageBytes);

      // 3. ページの作成 (画像サイズに合わせる)
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            decodedImage.width.toDouble(),
            decodedImage.height.toDouble(),
            marginAll: 0,
          ),
          build: (pw.Context context) {
            return pw.Stack(
              children: [
                // 最背面: レシート画像
                pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Image(pdfImage, fit: pw.BoxFit.cover),
                ),

                // 前面: 不可視テキストレイヤー
                // 行単位で配置することで、単語間の自然な選択を可能にする
                ...recognizedText.blocks.expand((block) {
                  return block.lines.map((line) {
                    final rect = line.boundingBox;

                    return pw.Positioned(
                      left: rect.left,
                      top: rect.top,
                      child: pw.Container(
                        width: rect.width,
                        height: rect.height,
                        // FittedBoxでOCRの枠に合わせて文字を強制伸縮させる
                        // これにより画像上の文字位置と選択範囲が完全に一致する
                        child: pw.FittedBox(
                          fit: pw.BoxFit.fill,
                          child: pw.Text(
                            line.text,
                            style: pw.TextStyle(
                              font: font,
                              fontSize: 10, // FittedBoxで拡大縮小されるので基準値でOK
                              // 【重要】色を透明にするのではなく、レンダリングモードを「不可視」にする
                              // これにより見た目には一切現れないが、データとしては存在し検索可能になる
                              renderingMode: PdfTextRenderingMode.invisible,
                            ),
                          ),
                        ),
                      ),
                    );
                  });
                }),
              ],
            );
          },
        ),
      );
    }

    return await pdf.save();
  }
}