import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receiptscanner/models/receipt_data.dart';

class AmountCandidate {
  final int value;
  final int lineIndex;
  final double lineHeight;
  final bool hasTotalKeyword;
  final bool isExcluded;
  final bool isTaxTarget;

  AmountCandidate({
    required this.value,
    required this.lineIndex,
    required this.lineHeight,
    required this.hasTotalKeyword,
    required this.isExcluded,
    required this.isTaxTarget,
  });

  @override
  String toString() {
    return 'Val:$value, Size:${lineHeight.toStringAsFixed(1)}, Total:$hasTotalKeyword, Excl:$isExcluded';
  }
}

class ReceiptParser {
  ReceiptData parse(RecognizedText recognizedText) {
    String text = _reconstructLineByLine(recognizedText);

    print('--- [DEBUG] Reconstructed Text Start ---');
    print(text);
    print('--- [DEBUG] Reconstructed Text End ---');

    String cleanedText = text
        .replaceAll(RegExp(r'[YyVJ]'), '¥')
        .replaceAll('￥', '¥')
        .replaceAll('％', '%');

    return _analyze(cleanedText, recognizedText);
  }

  ReceiptData _analyze(String text, RecognizedText originalData) {
    final lines = text.split('\n');

    String? storeName;
    DateTime? foundDate;
    String? foundTime;
    String? invoiceNum;
    String? tel;

    int? tax10;
    int? tax8;
    int? target10;
    int? target8;

    int currentTaxContext = 0;

    List<AmountCandidate> candidates = [];

    final datePatternJP = RegExp(r'(\d{4})\s*[\-/\.年]\s*(\d{1,2})\s*[\-/\.月]\s*(\d{1,2})');
    final datePatternShort = RegExp(r'(\d{1,2})\s*[\-/\.月]\s*(\d{1,2})\s*[日]?(?!\d{4})');
    final timePattern = RegExp(r'(\d{1,2})[:：](\d{2})');
    final telPattern = RegExp(r'\d{2,4}[-\s]\d{2,4}[-\s]\d{3,4}');

    // インボイス番号 (T + 数字13桁)
    final invoicePattern = RegExp(r'T\d{13}');

    // 金額抽出用
    final amountLoosePattern = RegExp(r'[¥]?\s?([0-9,.\s]+)');

    final totalRegex = RegExp(r'(合\s*計|お\s*買\s*上|支\s*払|請求|Total|TOTAL)');
    final excludeRegex = RegExp(r'(預|釣|返金|現\s*計|Cash|Change|Tender|No\.)'); // No.も除外候補に追加
    final taxTargetRegex = RegExp(r'(対象|税抜|外税|内税)');

    print('--- [DEBUG] Analysis Loop Start ---');

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) continue;

      print('Line [$i]: "$line"');

      // 1. インボイス番号
      // 先に判定して、この行を金額抽出から除外するためのフラグを立てる
      bool isInvoiceLine = false;
      if (invoiceNum == null) {
        final match = invoicePattern.firstMatch(line);
        if (match != null) {
          invoiceNum = match.group(0);
          isInvoiceLine = true;
        }
      }
      // "登録番号" という文字が含まれていたら、OCRでTが抜けていてもインボイス行とみなす
      if (line.contains('登録番号')) {
        isInvoiceLine = true;
      }

      // 2. 電話番号
      if (tel == null) {
        var match = telPattern.firstMatch(line);
        if (match != null) {
          tel = match.group(0);
        } else {
          if (line.contains('電話') || line.contains('TEL') || line.contains('Tel')) {
            String normalizedLine = line
                .replaceAll('B', '8')
                .replaceAll('D', '0')
                .replaceAll('O', '0')
                .replaceAll('Z', '2')
                .replaceAll('S', '5')
                .replaceAll('I', '1')
                .replaceAll('l', '1');
            match = telPattern.firstMatch(normalizedLine);
            if (match != null) {
              tel = match.group(0);
              print('    -> Found Tel after normalization: $tel');
            }
          }
        }
      }

      // 3. 日付
      if (foundDate == null) {
        var match = datePatternJP.firstMatch(line);
        if (match != null) {
          int y = int.parse(match.group(1)!);
          int m = int.parse(match.group(2)!);
          int d = int.parse(match.group(3)!);
          if (y >= 2000 && y <= 2100) foundDate = DateTime(y, m, d);
        } else {
          var matchShort = datePatternShort.firstMatch(line);
          if (matchShort != null) {
            int m = int.parse(matchShort.group(1)!);
            int d = int.parse(matchShort.group(2)!);
            int currentYear = DateTime.now().year;
            if (m >= 1 && m <= 12 && d >= 1 && d <= 31) foundDate = DateTime(currentYear, m, d);
          }
        }
      }

      // 4. 時間
      if (foundTime == null) {
        final match = timePattern.firstMatch(line);
        if (match != null) {
          int h = int.parse(match.group(1)!);
          int m = int.parse(match.group(2)!);
          if (h < 24 && m < 60) foundTime = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        }
      }

      // 5. 店舗名
      if (storeName == null && i < 5) {
        if (!line.contains(datePatternJP) &&
            !line.contains(telPattern) &&
            !line.contains('レシート') &&
            !line.contains('領収') &&
            line.length > 2) {
          storeName = line;
        }
      }

      // 6. 税率コンテキスト判定
      int lineTaxContext = 0;
      if (line.contains('10%') || line.contains('10％') || line.contains('標準')) {
        lineTaxContext = 10;
        currentTaxContext = 10;
      } else if (line.contains('8%') || line.contains('8％') || line.contains('軽')) {
        lineTaxContext = 8;
        currentTaxContext = 8;
      }

      // 7. 対象金額の抽出
      if (taxTargetRegex.hasMatch(line)) {
        List<int> nums = _extractNumbers(line);
        nums.removeWhere((n) => n == 8 || n == 10);

        if (nums.isNotEmpty) {
          nums.sort((a, b) => b.compareTo(a));
          int potentialTarget = nums.first;

          int context = lineTaxContext > 0 ? lineTaxContext : currentTaxContext;

          if (context == 10) {
            if (target10 == null) {
              target10 = potentialTarget;
              print('    -> [Target 10%] Found: $potentialTarget');
            }
          } else if (context == 8) {
            if (target8 == null) {
              target8 = potentialTarget;
              print('    -> [Target 8%] Found: $potentialTarget');
            }
          }
        }
      }

      // 8. 消費税額の抽出
      if ((line.contains('税') || line.contains('消費')) && !line.contains('対象')) {
        List<int> nums = _extractNumbers(line);
        nums.removeWhere((n) => n == 8 || n == 10);

        if (nums.isNotEmpty) {
          nums.sort();
          int potentialTax = nums.first;

          if (currentTaxContext == 10) {
            if (tax10 == null) tax10 = potentialTax;
          } else if (currentTaxContext == 8) {
            if (tax8 == null) tax8 = potentialTax;
          }
        }
      }

      // 9. 合計金額候補の収集
      // 【修正】インボイス番号の行や、電話番号が含まれる行は金額候補から除外する
      if (isInvoiceLine || line.contains('取引ID') || (tel != null && line.contains(tel))) {
        print('    -> Skipping logic for amount on this line (ID/Invoice/Tel)');
        continue;
      }

      bool isTotalLine = totalRegex.hasMatch(line);
      bool isExcludedLine = excludeRegex.hasMatch(line);
      bool isTaxTargetLine = taxTargetRegex.hasMatch(line);

      final amountMatches = amountLoosePattern.allMatches(line);
      for (final match in amountMatches) {
        String rawStr = match.group(1)!;
        String cleanStr = rawStr.replaceAll(RegExp(r'[,\s]'), '');

        // ヨークベニマルの "2.001" のようなドット誤読に対応
        // ドットが含まれている場合、ドットを除去して整数にする
        cleanStr = cleanStr.replaceAll('.', '');

        int? value = int.tryParse(cleanStr);
        if (value != null && value > 0) {
          candidates.add(AmountCandidate(
            value: value,
            lineIndex: i,
            lineHeight: 1.0,
            hasTotalKeyword: isTotalLine,
            isExcluded: isExcludedLine,
            isTaxTarget: isTaxTargetLine,
          ));
        }
      }
    }
    print('--- [DEBUG] Analysis Loop End ---');

    // --- 合計金額の決定 ---
    int? finalAmount;
    var validCandidates = candidates.where((c) => !c.isExcluded && !c.isTaxTarget).toList();

    if (validCandidates.isEmpty && candidates.isNotEmpty) {
      validCandidates = candidates;
    }

    if (validCandidates.isNotEmpty) {
      validCandidates.sort((a, b) {
        if (a.hasTotalKeyword && !b.hasTotalKeyword) return -1;
        if (!a.hasTotalKeyword && b.hasTotalKeyword) return 1;
        return b.value.compareTo(a.value);
      });

      finalAmount = validCandidates.first.value;
      print('  -> Selected Amount: $finalAmount');
    }

    if (foundDate != null && foundTime != null) {
      final parts = foundTime!.split(':');
      foundDate = DateTime(
          foundDate!.year, foundDate!.month, foundDate!.day,
          int.parse(parts[0]), int.parse(parts[1])
      );
    }

    return ReceiptData(
      storeName: storeName ?? '',
      date: foundDate,
      amount: finalAmount,
      targetAmount10: target10,
      targetAmount8: target8,
      taxAmount10: tax10,
      taxAmount8: tax8,
      invoiceNumber: invoiceNum,
      tel: tel,
      rawText: text,
    );
  }

  List<int> _extractNumbers(String line) {
    List<int> numbers = [];
    final matches = RegExp(r'(\d+(?:[,\.\s]+\d+)*)').allMatches(line);

    for (var m in matches) {
      String raw = m.group(0)!;
      String clean = raw.replaceAll(RegExp(r'[^0-9]'), '');

      int? val = int.tryParse(clean);
      if (val != null) numbers.add(val);
    }
    return numbers;
  }

  String _reconstructLineByLine(RecognizedText recognizedText) {
    List<TextLine> allLines = [];
    for (var block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }
    if (allLines.isEmpty) return "";

    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    List<List<TextLine>> groupedLines = [];
    List<TextLine> currentGroup = [allLines[0]];

    for (int i = 1; i < allLines.length; i++) {
      final line = allLines[i];
      final prevLine = currentGroup.last;

      double verticalThreshold = (prevLine.boundingBox.height + line.boundingBox.height) / 2 * 0.5;

      if ((line.boundingBox.center.dy - prevLine.boundingBox.center.dy).abs() < verticalThreshold) {
        currentGroup.add(line);
      } else {
        groupedLines.add(currentGroup);
        currentGroup = [line];
      }
    }
    groupedLines.add(currentGroup);

    StringBuffer resultBuffer = StringBuffer();
    for (var group in groupedLines) {
      group.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      String lineText = group.map((e) => e.text).join(' ');
      resultBuffer.writeln(lineText);
    }
    return resultBuffer.toString();
  }
}