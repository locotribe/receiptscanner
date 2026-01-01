// lib/widgets/receipt_list_item.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import '../models/receipt_data.dart';

class ReceiptListItem extends StatelessWidget {
  final ReceiptData item;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(BuildContext) onUpload;
  final Function(BuildContext) onDelete;

  const ReceiptListItem({
    super.key,
    required this.item,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // ファイル有無チェック
    bool fileExists = false;
    if (item.imagePath != null) {
      fileExists = File(item.imagePath!).existsSync();
    }

    // アイコン決定ロジック (4パターン)
    Widget leadingIcon;
    if (isSelectionMode) {
      leadingIcon = Icon(
        isSelected ? Icons.check_box : Icons.check_box_outline_blank,
        color: isSelected ? Colors.blue : Colors.grey,
        size: 30,
      );
    } else {
      if (item.isUploaded == 1) {
        // クラウドに画像あり
        if (fileExists) {
          leadingIcon = const Icon(Icons.check_circle, color: Colors.green, size: 30); // 完全同期
        } else {
          leadingIcon = const Icon(Icons.cloud_download, color: Colors.blue, size: 30); // クラウドのみ
        }
      } else {
        // クラウドに画像なし
        if (fileExists) {
          leadingIcon = const Icon(Icons.cloud_upload, color: Colors.grey, size: 30); // 未アップロード
        } else {
          // 端末にも画像なし (他端末で登録されたデータ)
          leadingIcon = const Icon(Icons.warning, color: Colors.orange, size: 30);
        }
      }
    }

    return Slidable(
      key: Key(item.id),
      enabled: !isSelectionMode,
      startActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: onUpload,
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            icon: Icons.cloud_upload,
            label: '保存',
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: onDelete,
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '削除',
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              bottomLeft: Radius.circular(4),
            ),
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: 2,
        color: isSelected ? Colors.blue.withOpacity(0.1) : null,
        child: ListTile(
          leading: leadingIcon,
          title: Text(
            item.storeName.isNotEmpty ? item.storeName : '店名なし',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            _buildSubtitle(item),
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          trailing: Text(
            '¥${item.amountFormatted}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ),
    );
  }

  String _buildSubtitle(ReceiptData item) {
    String dateStr = DateFormat('MM/dd HH:mm').format(item.date!);
    final formatter = NumberFormat("#,###");
    List<String> details = [];
    if (item.targetAmount10 != null) {
      String line = '10%: ¥${formatter.format(item.targetAmount10)}';
      if (item.taxAmount10 != null) line += ' (¥${formatter.format(item.taxAmount10)})';
      details.add(line);
    }
    if (item.targetAmount8 != null) {
      String line = ' 8%: ¥${formatter.format(item.targetAmount8)}';
      if (item.taxAmount8 != null) line += ' (¥${formatter.format(item.taxAmount8)})';
      details.add(line);
    }
    if (details.isNotEmpty) return '$dateStr\n${details.join('\n')}';
    return dateStr;
  }
}