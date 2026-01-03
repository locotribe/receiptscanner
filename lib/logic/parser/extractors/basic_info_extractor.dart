// lib/logic/parser/extractors/basic_info_extractor.dart
import '../receipt_text_util.dart';

class BasicInfoResult {
  final DateTime? date;
  final String storeName;
  final String? tel;
  final String? invoiceNum;

  BasicInfoResult({
    this.date,
    required this.storeName,
    this.tel,
    this.invoiceNum,
  });
}

class BasicInfoExtractor {
  static BasicInfoResult extract(List<String> lines) {
    print('[DEBUG] [BasicInfo] --- 基本情報抽出開始 ---');

    DateTime? date;
    String storeName = '';
    String? tel;
    String? invoiceNum;

    // --- 1. 電話番号抽出 ---
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

    // 電話番号: キーワードあり行を優先探索
    for (var line in lines) {
      if (line.contains(RegExp(r'20\d{2}'))) continue; // 年号を含む行は誤検出防止のためスキップ
      if (!line.contains(telKeywords)) continue;
      String? result = extractPhone(line);
      if (result != null) {
        tel = result;
        print('[DEBUG] [BasicInfo] 電話番号検出(キーワード優先): $tel');
        break;
      }
    }
    // 電話番号: 見つからなければ全体探索
    if (tel == null) {
      for (var line in lines) {
        if (line.contains(RegExp(r'20\d{2}'))) continue;
        if (line.contains(telKeywords)) continue; // 既にチェック済み
        if (line.contains(excludeKeywords)) continue;
        String? result = extractPhone(line);
        if (result != null) {
          tel = result;
          print('[DEBUG] [BasicInfo] 電話番号検出(全体): $tel');
          break;
        }
      }
    }

    // --- 2. インボイス番号抽出 ---
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
      bool hasKeyword = invoiceKeywords.any((k) => line.contains(k));
      bool looksLikeInvoice = RegExp(r'T[\s\-]?[0-9OQDBIZS]{5,}', caseSensitive: false).hasMatch(line);
      if (!hasKeyword && !looksLikeInvoice) continue;

      // 正規化
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
          print('[DEBUG] [BasicInfo] インボイス番号検出: $invoiceNum');
          break;
        }
      }
    }

    // --- 3. 日付抽出 ---
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
          print('[DEBUG] [BasicInfo] 日付検出: $date');
          break;
        } catch (_) {}
      }
    }

    // --- 4. 店名抽出 (簡易ロジック) ---
    for (int i = 0; i < lines.length && i < 5; i++) {
      String l = lines[i].trim();
      if (l.isEmpty) continue;
      if (l.contains('レシート') || l.contains('領収') || looseTelRegex.hasMatch(l) || dateRegex.hasMatch(l)) continue;
      if (RegExp(r'^[\d\s¥,.\-*]+$').hasMatch(l)) continue;
      storeName = l;
      print('[DEBUG] [BasicInfo] 店名候補(簡易): $storeName');
      break;
    }

    return BasicInfoResult(
      date: date,
      storeName: storeName,
      tel: tel,
      invoiceNum: invoiceNum,
    );
  }
}