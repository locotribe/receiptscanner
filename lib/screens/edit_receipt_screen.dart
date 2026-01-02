// lib/screens/edit_receipt_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';

import '../models/receipt_data.dart';
import '../logic/pdf_generator.dart';
import '../database/database_helper.dart';
import '../utils/date_picker_util.dart';

class EditReceiptScreen extends StatefulWidget {
  final ReceiptData initialData;
  final bool isEditing;
  const EditReceiptScreen({super.key, required this.initialData, this.isEditing = false});
  @override
  State<EditReceiptScreen> createState() => _EditReceiptScreenState();
}

class _EditReceiptScreenState extends State<EditReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  // 【修正】税額用コントローラー(_tax10Controller, _tax8Controller)を削除
  late TextEditingController _storeController, _amountController, _target10Controller, _target8Controller, _telController, _dateController, _timeController, _invoiceController, _descriptionController;
  final _pdfGenerator = PdfGenerator();
  Uint8List? _pdfImageBytes;

  // 【追加】保存中かどうかを管理するフラグ
  bool _isSaving = false;

  final _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _storeController = TextEditingController(text: d.storeName);
    _amountController = TextEditingController(text: d.amount?.toString() ?? '');
    _target10Controller = TextEditingController(text: d.targetAmount10?.toString() ?? '');
    // 税額は表示しないためコントローラー初期化不要
    _target8Controller = TextEditingController(text: d.targetAmount8?.toString() ?? '');

    _telController = TextEditingController(text: _formatInitialTel(d.tel));
    _dateController = TextEditingController(text: d.dateString);
    _timeController = TextEditingController(text: d.timeString);
    _invoiceController = TextEditingController(text: d.invoiceNumber);
    _descriptionController = TextEditingController(text: d.description);

    _amountController.addListener(_onAmountChanged);
    // 税額計算用のリスナーは不要になったため削除

    _loadPdfImageIfNeeded();
  }

  Future<void> _loadPdfImageIfNeeded() async {
    final path = widget.initialData.imagePath;
    if (path != null && path.toLowerCase().endsWith('.pdf')) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          await for (final page in Printing.raster(bytes, pages: [0])) {
            final image = await page.toPng();
            if (mounted) {
              setState(() {
                _pdfImageBytes = image;
              });
            }
            break;
          }
        }
      } catch (e) {
        print('Error loading PDF preview: $e');
      }
    }
  }

  String _formatInitialTel(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (raw.contains('-')) return raw;
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return raw;
    if (digits.length == 10) {
      if (digits.startsWith('03') || digits.startsWith('06')) {
        return '${digits.substring(0,2)}-${digits.substring(2,6)}-${digits.substring(6)}';
      } else {
        return '${digits.substring(0,3)}-${digits.substring(3,6)}-${digits.substring(6)}';
      }
    } else if (digits.length == 11) {
      return '${digits.substring(0,3)}-${digits.substring(3,7)}-${digits.substring(7)}';
    }
    return digits;
  }

  void _onAmountChanged() {
    if (_amountController.text.isEmpty) return;
    int? total = int.tryParse(_amountController.text.replaceAll(',', ''));
    // 合計金額が入力され、8%対象が空の場合は、全額を10%対象(税込)としてセットする
    if (total != null && total > 0 && _target8Controller.text.isEmpty) {
      _target10Controller.text = total.toString();
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _storeController.dispose(); _amountController.dispose(); _target10Controller.dispose();
    _target8Controller.dispose(); _telController.dispose(); _dateController.dispose();
    _timeController.dispose(); _invoiceController.dispose();
    _descriptionController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    DateTime initial = DateTime.now();
    try { if (_dateController.text.isNotEmpty) initial = DateFormat('yyyy-MM-dd').parse(_dateController.text); } catch (_) {}
    await DatePickerUtil.showJapaneseDatePicker(context, initial, (newDate) {
      setState(() => _dateController.text = DateFormat('yyyy-MM-dd').format(newDate));
    });
  }

  Future<void> _pickTime() async {
    TimeOfDay initial = TimeOfDay.now();
    try { if (_timeController.text.isNotEmpty) { final parts = _timeController.text.split(':'); initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])); } } catch (_) {}
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) setState(() => _timeController.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _saveData() async {
    // 保存中は連打できないようにする
    if (_isSaving) return;

    if (_formKey.currentState!.validate()) {
      final storeName = _storeController.text;
      final amountStr = _amountController.text.replaceAll(',', '');
      final amount = int.tryParse(amountStr);

      // 対象額(税込)を取得
      final target10 = int.tryParse(_target10Controller.text.replaceAll(',', ''));
      final target8 = int.tryParse(_target8Controller.text.replaceAll(',', ''));

      // 【修正】税額は入力値(税込対象額)から自動計算する
      int? tax10;
      if (target10 != null) {
        tax10 = (target10 * 10 / 110).floor();
      }

      int? tax8;
      if (target8 != null) {
        tax8 = (target8 * 8 / 108).floor();
      }

      final date = _dateController.text;
      final time = _timeController.text;
      final invoice = _invoiceController.text;
      final tel = _telController.text;
      final description = _descriptionController.text;

      String telRaw = tel.replaceAll(RegExp(r'[^0-9]'), '');
      String formattedTel = telRaw;
      if (telRaw.length == 10) {
        if (telRaw.startsWith('03') || telRaw.startsWith('06')) {
          formattedTel = '${telRaw.substring(0,2)}-${telRaw.substring(2,6)}-${telRaw.substring(6)}';
        } else {
          formattedTel = '${telRaw.substring(0,3)}-${telRaw.substring(3,6)}-${telRaw.substring(6)}';
        }
      } else if (telRaw.length == 11) {
        formattedTel = '${telRaw.substring(0,3)}-${telRaw.substring(3,7)}-${telRaw.substring(7)}';
      }
      if (tel.contains('-') && tel.length > 9) {
        formattedTel = tel;
      }

      DateTime? dateTime;
      try { if (date.isNotEmpty) { String t = time.isEmpty ? '00:00' : time; dateTime = DateFormat('yyyy-MM-dd HH:mm').parse('$date $t'); } } catch (_) {}

      if (dateTime != null && amount != null) {
        final isDuplicate = await DatabaseHelper.instance.checkDuplicate(dateTime, amount, excludeId: widget.initialData.id);
        if (isDuplicate) {
          if (!mounted) return;
          final shouldSave = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('重複の確認'),
              content: Text('修正後の日時と金額(${NumberFormat("#,###").format(amount)}円)は\n既に登録済みです。\n本当に保存しますか？', style: const TextStyle(fontSize: 16)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('やめる')),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('重複して保存')),
              ],
            ),
          );
          if (shouldSave != true) return;
        }
      }

      // 【追加】ここから重い処理が始まるのでローディング表示を開始
      setState(() {
        _isSaving = true;
      });

      // try-finally ブロックでエラー時も確実にローディングを解除できるようにする（画面遷移しない場合）
      try {
        final dateStr = date.replaceAll('-', '');
        final safeStoreName = storeName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final timestamp = DateFormat('HHmmss').format(DateTime.now());
        final fileName = '${dateStr}_${timestamp}_${safeStoreName}_$amountStr.pdf';

        final appDir = await getApplicationDocumentsDirectory();
        final saveDir = Directory('${appDir.path}/receipts');
        if (!await saveDir.exists()) {
          await saveDir.create(recursive: true);
        }
        final savePath = '${saveDir.path}/$fileName';

        try {
          if (widget.initialData.imagePath != null && widget.initialData.ocrData != null) {
            final pdfBytes = await _pdfGenerator.generateSearchablePdf(
                widget.initialData.imagePath!,
                widget.initialData.ocrData!
            );
            final file = File(savePath);
            await file.writeAsBytes(pdfBytes);
            print('PDF Saved: $savePath');
          } else {
            // OCRデータなしの場合の処理
          }
        } catch (e) {
          print('PDF生成エラー: $e');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF生成に失敗しました')));

          // エラーの場合はローディングを解除してリターン
          setState(() {
            _isSaving = false;
          });
          return;
        }

        String id = widget.initialData.id;
        if (id.isEmpty) { id = '${storeName}_${date.replaceAll('-', '')}${time.replaceAll(':', '')}$amount'; }

        String finalImagePath = widget.initialData.imagePath ?? '';
        if (widget.initialData.ocrData != null) {
          finalImagePath = savePath;
        }

        final saveData = ReceiptData(
          id: id, storeName: storeName, date: dateTime, amount: amount,
          targetAmount10: target10, targetAmount8: target8, taxAmount10: tax10, taxAmount8: tax8,
          invoiceNumber: invoice, tel: formattedTel, rawText: widget.initialData.rawText,
          imagePath: finalImagePath,
          description: description,
        );

        // --- 学習機能の呼び出し ---
        // ユーザーが入力した摘要と、OCRの生テキストを学習させる
        await DatabaseHelper.instance.updateCategoryLearning(
          widget.initialData.rawText,
          description,
        );

        await DatabaseHelper.instance.insertReceipt(saveData);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存しました')));
        Navigator.pop(context, true);
      } catch (e) {
        // 万が一その他のエラーが発生した場合
        print('保存エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
          setState(() {
            _isSaving = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget backgroundContent;
    if (widget.initialData.imagePath != null && widget.initialData.imagePath!.toLowerCase().endsWith('.pdf')) {
      if (_pdfImageBytes != null) {
        backgroundContent = Image.memory(_pdfImageBytes!, fit: BoxFit.contain);
      } else {
        backgroundContent = const Center(child: CircularProgressIndicator());
      }
    } else if (widget.initialData.imagePath != null) {
      backgroundContent = Image.file(File(widget.initialData.imagePath!), fit: BoxFit.contain);
    } else {
      backgroundContent = const Center(child: Icon(Icons.receipt, size: 100, color: Colors.grey));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.isEditing ? '詳細・編集' : '内容確認'),
        backgroundColor: Colors.black.withOpacity(0.5),
        foregroundColor: Colors.white,
        actions: [
          if (!widget.isEditing) IconButton(onPressed: _isSaving ? null : () => Navigator.pop(context, 'rescan'), icon: const Icon(Icons.camera_alt)),
          // 保存中はボタンを無効化（見た目上は押せそうでも、_saveData冒頭でガード済み）
          IconButton(onPressed: _saveData, icon: const Icon(Icons.save)),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _transformationController.value = Matrix4.identity();
              },
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.1,
                maxScale: 10.0,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Container(
                  color: Colors.black,
                  padding: EdgeInsets.symmetric(
                    vertical: MediaQuery.of(context).size.height * 0.1,
                  ),
                  child: Center(child: backgroundContent),
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.15,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 5)],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 5,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        TextFormField(controller: _storeController, decoration: const InputDecoration(labelText: '店名')),
                        const SizedBox(height: 12),
                        TextFormField(controller: _descriptionController, decoration: const InputDecoration(labelText: '摘要 (科目：消耗品、食材など)')),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(flex: 3, child: TextFormField(controller: _dateController, decoration: const InputDecoration(labelText: '日付'), readOnly: true, onTap: _pickDate)),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: TextFormField(controller: _timeController, decoration: const InputDecoration(labelText: '時間'), readOnly: true, onTap: _pickTime)),
                        ]),
                        const SizedBox(height: 12),
                        TextFormField(controller: _amountController, decoration: const InputDecoration(labelText: '合計金額 (税込)'), keyboardType: TextInputType.number),
                        const SizedBox(height: 8),

                        // 【修正】税額入力欄を削除し、対象額のみを表示
                        Row(children: [
                          const Text('10%', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 16),
                          Expanded(child: TextFormField(controller: _target10Controller, decoration: const InputDecoration(labelText: '対象計 (税込)'), keyboardType: TextInputType.number)),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Text(' 8%', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 16),
                          Expanded(child: TextFormField(controller: _target8Controller, decoration: const InputDecoration(labelText: '対象計 (税込)'), keyboardType: TextInputType.number)),
                        ]),

                        const SizedBox(height: 12),
                        TextFormField(controller: _invoiceController, decoration: const InputDecoration(labelText: 'インボイス登録番号')),
                        const SizedBox(height: 12),
                        TextFormField(
                            controller: _telController,
                            decoration: const InputDecoration(labelText: '電話番号', hintText: '0245440901 (ハイフンなしでもOK)'),
                            keyboardType: TextInputType.phone
                        ),
                        const SizedBox(height: 32),
                        SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _isSaving ? null : _saveData, icon: const Icon(Icons.save), label: const Text('保存する'), style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary))),
                        SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // 【追加】保存中のローディングオーバーレイ
          if (_isSaving)
            Container(
              color: Colors.black.withOpacity(0.6), // 少し濃いめの半透明
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '保存中...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}