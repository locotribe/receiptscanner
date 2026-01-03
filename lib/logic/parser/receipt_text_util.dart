// lib/logic/parser/receipt_text_util.dart
import 'dart:math';

class ReceiptTextUtil {
  /// 金額解析用の文字クリーニング
  static String normalizeAmountText(String text) {
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
  static List<int> extractValues(String text) {
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

  static bool areSimilar(String a, String b) {
    if ((a.length - b.length).abs() > 3) return false;
    int matchCount = 0;
    int len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      if (a[i] == b[i]) matchCount++;
    }
    return (matchCount / len) > 0.7;
  }
}