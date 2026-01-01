// lib/logic/receipt_action_helper.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/receipt_data.dart';
import '../database/database_helper.dart';
import '../logic/google_drive_service.dart';
import '../logic/auth_service.dart';

class ReceiptActionHelper {
  /// ファイル名生成ロジック
  static String _generateFileName(ReceiptData item) {
    final datePart = DateFormat('yyyy_MMdd').format(item.date!);
    final timePart = DateFormat('HHmm').format(item.date!);
    String safeStoreName = item.storeName.isNotEmpty ? item.storeName : 'NoName';
    safeStoreName = safeStoreName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final extension = item.imagePath!.split('.').last;
    return "${datePart}_${timePart}_${safeStoreName}_${item.amount ?? 0}.$extension";
  }

  /// 単体アップロード処理
  static Future<void> uploadReceipt(
      BuildContext context, ReceiptData item, VoidCallback onSuccess) async {
    if (AuthService.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('左上のメニューからGoogleアカウントと連携してください')));
      return;
    }

    if (item.imagePath == null || !File(item.imagePath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('アップロードするファイルが端末にありません。')));
      return;
    }

    if (item.date == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日付が設定されていないため保存できません')));
      return;
    }

    if (item.isUploaded == 1 && item.driveFileId != null) {
      final bool? shouldOverwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('上書きの確認'),
          content: const Text('このレシートは既に保存されています。\n古いファイルを削除して上書きしますか？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                child: const Text('上書きする')),
          ],
        ),
      );
      if (shouldOverwrite != true) return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Googleドライブへアップロード中...')));

    try {
      if (item.isUploaded == 1 && item.driveFileId != null) {
        await GoogleDriveService.instance.deleteFile(item.driveFileId!);
      }

      final file = File(item.imagePath!);
      final fileName = _generateFileName(item);
      final fileId = await GoogleDriveService.instance.uploadFile(file, fileName, item.date!);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (fileId != null) {
        await DatabaseHelper.instance.updateUploadStatus(item.id, fileId);

        // 同期更新
        final updatedItem = item;
        updatedItem.isUploaded = 1;
        updatedItem.driveFileId = fileId;
        await GoogleDriveService.instance.syncReceiptToCloud(updatedItem);

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$fileName」を保存しました')));
        onSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('アップロードに失敗しました')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
      }
    }
  }

  /// 一括アップロード処理
  static Future<void> uploadSelectedReceipts(
      BuildContext context, List<ReceiptData> selectedItems, VoidCallback onComplete) async {
    if (AuthService.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('左上のメニューからGoogleアカウントと連携してください')));
      return;
    }
    if (selectedItems.isEmpty) return;

    final hasUploadedItems = selectedItems.any((item) => item.isUploaded == 1 && item.driveFileId != null);
    bool skipUploaded = false;

    if (hasUploadedItems) {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重複ファイルの確認'),
          content: const Text('選択したレシートの中に、既に保存済みのファイルが含まれています。\nどうしますか？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('キャンセル')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: const Text('未保存のみ実行')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'overwrite'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                child: const Text('すべて上書き')),
          ],
        ),
      );
      if (result == 'cancel' || result == null) return;
      if (result == 'skip') skipUploaded = true;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
          canPop: false,
          child: AlertDialog(
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [CircularProgressIndicator(), SizedBox(height: 16), Text('アップロード中...')]
              )
          )
      ),
    );

    int successCount = 0;
    int errorCount = 0;

    for (var item in selectedItems) {
      if (skipUploaded && item.isUploaded == 1) continue;
      try {
        if (item.imagePath == null || !File(item.imagePath!).existsSync() || item.date == null) {
          errorCount++;
          continue;
        }
        if (item.isUploaded == 1 && item.driveFileId != null) {
          await GoogleDriveService.instance.deleteFile(item.driveFileId!);
        }

        final file = File(item.imagePath!);
        final fileName = _generateFileName(item);
        final fileId = await GoogleDriveService.instance.uploadFile(file, fileName, item.date!);

        if (fileId != null) {
          await DatabaseHelper.instance.updateUploadStatus(item.id, fileId);

          // 同期更新
          final updatedItem = item;
          updatedItem.isUploaded = 1;
          updatedItem.driveFileId = fileId;
          await GoogleDriveService.instance.syncReceiptToCloud(updatedItem);

          successCount++;
        } else {
          errorCount++;
        }
      } catch (e) {
        errorCount++;
      }
    }

    if (!context.mounted) return;
    Navigator.pop(context); // Progress Dialog Close

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('完了: 成功 $successCount件 / 失敗 $errorCount件')));
    onComplete();
  }

  /// スマート削除処理 (一括)
  static Future<void> deleteSelectedReceipts(
      BuildContext context, List<ReceiptData> selectedItems, VoidCallback onComplete) async {
    final uploadedItems = selectedItems.where((r) => r.isUploaded == 1).toList();
    final notUploadedItems = selectedItems.where((r) => r.isUploaded == 0).toList();

    String message = '';
    bool isDangerous = false;

    if (notUploadedItems.isNotEmpty) {
      message = '選択した項目のうち ${notUploadedItems.length}件 はまだバックアップされていません。\nこれらは完全に削除されます。\n\n';
      isDangerous = true;
    }
    if (uploadedItems.isNotEmpty) {
      message += 'バックアップ済みの ${uploadedItems.length}件 は、端末から画像のみを削除して容量を空けます。（リストには残ります）';
    } else if (notUploadedItems.isEmpty && uploadedItems.isEmpty) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDangerous ? '完全削除の確認' : '容量の確保'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: isDangerous ? Colors.red : Colors.blue),
              child: Text(isDangerous ? '削除する' : '実行')),
        ],
      ),
    );

    if (confirm != true) return;

    for (var item in selectedItems) {
      if (item.isUploaded == 1) {
        // ファイルのみ削除
        if (item.imagePath != null) {
          final file = File(item.imagePath!);
          if (file.existsSync()) await file.delete();
        }
      } else {
        // 完全削除
        if (item.imagePath != null) {
          final file = File(item.imagePath!);
          if (file.existsSync()) await file.delete();
        }
        await DatabaseHelper.instance.deleteReceipt(item.id);
        // クラウドのマスターデータからも削除
        await GoogleDriveService.instance.deleteReceiptFromCloud(item.id);
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('処理が完了しました')));
    onComplete();
  }

  /// 単体削除処理
  static Future<void> confirmDelete(
      BuildContext context, ReceiptData item, VoidCallback onComplete) async {
    String message;
    bool isDangerous;
    if (item.isUploaded == 1) {
      message = 'このレシートはバックアップ済みです。\n端末から画像を削除して容量を空けますか？\n（リストには残ります）';
      isDangerous = false;
    } else {
      message = 'このレシートはバックアップされていません。\n完全に削除してもよろしいですか？';
      isDangerous = true;
    }

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除の確認'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: isDangerous ? Colors.red : Colors.blue),
              child: Text(isDangerous ? '削除する' : '実行')),
        ],
      ),
    );

    if (shouldDelete == true) {
      if (item.isUploaded == 1) {
        if (item.imagePath != null) {
          final file = File(item.imagePath!);
          if (file.existsSync()) await file.delete();
        }
      } else {
        await DatabaseHelper.instance.deleteReceipt(item.id);
        // クラウド削除
        await GoogleDriveService.instance.deleteReceiptFromCloud(item.id);
      }
      onComplete();
    }
  }
}