import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receiptscanner/models/receipt_data.dart';

class AmountCandidate {
  final int value;
  final int lineIndex;
  final double lineHeight;
  final bool hasTotalKeyword;
  final bool hasYenSymbol;
  final bool isExcluded;
  final bool isTaxTarget;

  AmountCandidate({
    required this.value,
    required this.lineIndex,
    required this.lineHeight,
    required this.hasTotalKeyword,
    required this.hasYenSymbol,
    required this.isExcluded,
    required this.isTaxTarget,
  });

  @override
  String toString() {
    return 'Val:$value, Yen:$hasYenSymbol, Total:$hasTotalKeyword, Excl:$isExcluded';
  }
}

class ReceiptParser {

  static const List<String> _totalKeywords = ['合計', 'お買上', '支払', '請求', 'Total', 'TOTAL'];
  static const List<String> _targetKeywordsFuzzy = ['対象'];
  static const List<String> _targetKeywordsStrict = ['税抜', '外税', '内税', '対縁', '課税'];
  static const List<String> _excludeKeywordsLong = ['返金', '現計', 'Cash', 'Change', 'Tender'];
  static const List<String> _excludeKeywordsShort = ['預', '頂', '項', '順', '釣', '約', '杓', '的', 'No.'];
  static final _taxIncludedRegex = RegExp(r'(内税|税込|内消)');

  ReceiptData parse(RecognizedText recognizedText) {
    String text = _reconstructLineByLine(recognizedText);
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

    int? target10;
    int? target8;

    List<int> tax10Candidates = [];
    List<int> tax8Candidates = [];

    int currentTaxContext = 0;
    bool isTaxIncludedMode = false;

    List<AmountCandidate> candidates = [];

    final datePatternJP = RegExp(r'(\d{4})\s*[\-/\.年]\s*(\d{1,2})\s*[\-/\.月]\s*(\d{1,2})');
    final datePatternShort = RegExp(r'(\d{1,2})\s*[\-/\.月]\s*(\d{1,2})\s*[日]?(?!\d{4})');
    final timePatternColon = RegExp(r'(\d{1,2})[:：](\d{2})');
    final timePatternJP = RegExp(r'(\d{1,2})時(\d{1,2})分');
    final telPatternStrict = RegExp(r'\d{2,4}[-\s]\d{2,4}[-\s]\d{3,4}');
    final telPatternLoose = RegExp(r'\d{9,11}');
    final invoicePattern = RegExp(r'T\d{13}');
    final amountLoosePattern = RegExp(r'[¥]?\s?([0-9,.\s]+)');

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) continue;

      if (_taxIncludedRegex.hasMatch(line)) {
        isTaxIncludedMode = true;
      }

      // 1. インボイス番号
      bool isInvoiceLine = false;
      if (invoiceNum == null) {
        final match = invoicePattern.firstMatch(line);
        if (match != null) {
          invoiceNum = match.group(0);
          isInvoiceLine = true;
        }
      }
      if (_containsFuzzy(line, ['登録番号'])) {
        isInvoiceLine = true;
      }

      // 2. 電話番号
      if (tel == null) {
        var match = telPatternStrict.firstMatch(line);
        if (match != null) {
          tel = match.group(0);
        } else {
          if (_containsFuzzy(line, ['電話', 'TEL', 'Tel'])) {
            String normalizedLine = line
                .replaceAll('B', '8')
                .replaceAll('D', '0')
                .replaceAll('O', '0')
                .replaceAll('Z', '2')
                .replaceAll('S', '5')
                .replaceAll('I', '1')
                .replaceAll('l', '1');
            match = telPatternStrict.firstMatch(normalizedLine);
            if (match != null) {
              tel = match.group(0);
            } else {
              var looseMatch = telPatternLoose.firstMatch(normalizedLine.replaceAll(RegExp(r'[^0-9]'), ''));
              if (looseMatch != null) {
                tel = looseMatch.group(0);
              }
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
        var match = timePatternColon.firstMatch(line);
        if (match != null) {
          int h = int.parse(match.group(1)!);
          int m = int.parse(match.group(2)!);
          if (h < 24 && m < 60) foundTime = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        } else {
          var matchJP = timePatternJP.firstMatch(line);
          if (matchJP != null) {
            int h = int.parse(matchJP.group(1)!);
            int m = int.parse(matchJP.group(2)!);
            if (h < 24 && m < 60) foundTime = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
          }
        }
      }

      // 5. 店舗名
      if (storeName == null && i < 5) {
        if (!line.contains(datePatternJP) &&
            !line.contains(telPatternStrict) &&
            !_containsFuzzy(line, ['レシート', '領収']) &&
            line.length > 2) {
          storeName = line;
        }
      }

      // 6. 税率コンテキスト
      int lineTaxContext = 0;
      if (line.contains('10%') || line.contains('10％') || line.contains('標準')) {
        lineTaxContext = 10;
        currentTaxContext = 10;
      } else if (line.contains('8%') || line.contains('8％') || line.contains('軽')) {
        lineTaxContext = 8;
        currentTaxContext = 8;
      }

      // 7. 対象金額
      bool matchesTargetKeyword = _containsFuzzy(line, _targetKeywordsFuzzy);
      if (!matchesTargetKeyword) {
        for (var word in _targetKeywordsStrict) {
          if (line.contains(word)) {
            matchesTargetKeyword = true;
            break;
          }
        }
      }
      if (matchesTargetKeyword && line.contains('税込')) {
        if (!_containsFuzzy(line, ['対象']) && !line.contains('対縁') && !line.contains('課税')) {
          matchesTargetKeyword = false;
        }
      }

      if (matchesTargetKeyword) {
        List<int> nums = _extractNumbers(line);
        nums.removeWhere((n) => n == 8 || n == 10);
        if (nums.isNotEmpty) {
          nums.sort((a, b) => b.compareTo(a));
          int potentialTarget = nums.first;
          int context = lineTaxContext > 0 ? lineTaxContext : currentTaxContext;
          if (context == 10) {
            if (target10 == null) target10 = potentialTarget;
          } else if (context == 8) {
            if (target8 == null) target8 = potentialTarget;
          }
        }
      }

      // 8. 消費税額
      if ((line.contains('税') || line.contains('消費')) &&
          !matchesTargetKeyword &&
          !line.contains('税込')) {

        List<int> nums = _extractNumbers(line);
        nums.removeWhere((n) => n == 8 || n == 10);

        if (nums.isNotEmpty) {
          if (currentTaxContext == 10) {
            tax10Candidates.addAll(nums);
          } else if (currentTaxContext == 8) {
            tax8Candidates.addAll(nums);
          }
        }
      }

      // 9. 合計金額候補
      if (isInvoiceLine || line.contains('取引ID') || (tel != null && line.contains(tel))) {
        continue;
      }
      if (line.contains('-') || line.contains('/')) {
        continue;
      }

      bool isTotalLine = _containsFuzzy(line, _totalKeywords);
      bool isExcludedLine = false;
      for (var word in _excludeKeywordsShort) {
        if (line.contains(word)) { isExcludedLine = true; break; }
      }
      if (!isExcludedLine) {
        isExcludedLine = _containsFuzzy(line, _excludeKeywordsLong);
      }
      bool isTaxTargetLine = matchesTargetKeyword;
      bool hasYen = line.contains('¥') || line.contains('円');

      final amountMatches = amountLoosePattern.allMatches(line);
      for (final match in amountMatches) {
        String rawStr = match.group(1)!;
        String cleanStr = rawStr.replaceAll(RegExp(r'[,\s]'), '').replaceAll('.', '');
        int? value = int.tryParse(cleanStr);

        if (value != null && value > 1000000) continue;

        if (value != null && value > 0) {
          candidates.add(AmountCandidate(
            value: value,
            lineIndex: i,
            lineHeight: 1.0,
            hasTotalKeyword: isTotalLine,
            hasYenSymbol: hasYen,
            isExcluded: isExcludedLine,
            isTaxTarget: isTaxTargetLine,
          ));
        }
      }
    }

    // --- 後処理 ---

    int? finalTax10 = _selectBestTax(tax10Candidates, target10, 0.10);
    int? finalTax8 = _selectBestTax(tax8Candidates, target8, 0.08);

    int? finalAmount;
    var validCandidates = candidates.where((c) => !c.isExcluded && !c.isTaxTarget).toList();
    if (validCandidates.isEmpty && candidates.isNotEmpty) validCandidates = candidates;

    if (validCandidates.isNotEmpty) {
      validCandidates.sort((a, b) {
        bool aMatchesTax = (target10 != null && a.value == target10) || (target8 != null && a.value == target8);
        bool bMatchesTax = (target10 != null && b.value == target10) || (target8 != null && b.value == target8);

        if (isTaxIncludedMode) {
          if (aMatchesTax && !bMatchesTax) return -1;
          if (!aMatchesTax && bMatchesTax) return 1;
        }

        if (a.hasTotalKeyword && !b.hasTotalKeyword) return -1;
        if (!a.hasTotalKeyword && b.hasTotalKeyword) return 1;

        if (!isTaxIncludedMode) {
          if (aMatchesTax && !bMatchesTax) return -1;
          if (!aMatchesTax && bMatchesTax) return 1;
        }

        if (a.hasYenSymbol && !b.hasYenSymbol) return -1;
        if (!a.hasYenSymbol && b.hasYenSymbol) return 1;
        return b.value.compareTo(a.value);
      });
      finalAmount = validCandidates.first.value;
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
      taxAmount10: finalTax10,
      taxAmount8: finalTax8,
      invoiceNumber: invoiceNum,
      tel: tel,
      rawText: text,
      ocrData: originalData,
    );
  }

  int? _selectBestTax(List<int> candidates, int? target, double rate) {
    if (candidates.isEmpty) return null;
    if (target == null) return candidates.first;

    int expectedTax = (target * rate).round();
    int bestCandidate = candidates.first;
    int minDiff = (candidates.first - expectedTax).abs();

    for (int val in candidates) {
      int diff = (val - expectedTax).abs();

      String valStr = val.toString();
      int valStripped = val;
      if (val > expectedTax * 5 && valStr.length > 1) {
        try {
          valStripped = int.parse(valStr.substring(1));
        } catch (_) {}
      }
      int diffStripped = (valStripped - expectedTax).abs();

      if (diff < minDiff) {
        minDiff = diff;
        bestCandidate = val;
      }
      if (diffStripped < minDiff) {
        minDiff = diffStripped;
        bestCandidate = valStripped;
      }
    }
    return bestCandidate;
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

  bool _containsFuzzy(String line, List<String> keywords, {int threshold = 1}) {
    for (final keyword in keywords) {
      if (keyword.length <= 2) {
        if (line.contains(keyword)) return true;
        continue;
      }
      if (line.contains(keyword)) return true;
      if (line.length < keyword.length) continue;
      for (int i = 0; i <= line.length - keyword.length; i++) {
        String sub = line.substring(i, i + keyword.length);
        if (_levenshtein(sub, keyword) <= threshold) {
          return true;
        }
      }
    }
    return false;
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);
    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }
}