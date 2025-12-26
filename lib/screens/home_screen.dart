import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

// 別ファイルからインポート
import '../models/receipt_data.dart';
import '../logic/receipt_parser.dart';
import '../database/database_helper.dart';
import '../utils/date_picker_util.dart';
import 'edit_receipt_screen.dart';
// 新規追加: 認証サービスとドロワー
import '../logic/auth_service.dart';
import 'components/app_drawer.dart';

class ScannerHomeScreen extends StatefulWidget {
  const ScannerHomeScreen({super.key});

  @override
  State<ScannerHomeScreen> createState() => _ScannerHomeScreenState();
}

class _ScannerHomeScreenState extends State<ScannerHomeScreen> with TickerProviderStateMixin {
  DocumentScanner? _documentScanner;
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.japanese);
  final _parser = ReceiptParser();

  bool _isProcessing = false;

  List<ReceiptData> _allReceipts = [];
  List<int> _availableYears = [];
  late DateTime _currentDisplayDate;
  late TabController _tabController;

  final List<int> _months = List.generate(12, (index) => index + 1);

  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  int? _filterMinAmount;
  int? _filterMaxAmount;

  @override
  void initState() {
    super.initState();
    _currentDisplayDate = DateTime.now();

    _tabController = TabController(
      length: _months.length,
      vsync: this,
      initialIndex: _currentDisplayDate.month - 1,
    );
    _tabController.addListener(_handleTabSelection);

    _initScanner();
    _loadReceipts();

    // アプリ起動時にログイン状態を確認・復元
    AuthService.instance.signInSilently();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      final selectedMonth = _months[_tabController.index];
      _currentDisplayDate = DateTime(_currentDisplayDate.year, selectedMonth);
    });
  }

  void _initScanner() {
    _documentScanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.full,
        pageLimit: 1,
        isGalleryImport: true,
      ),
    );
  }

  Future<void> _loadReceipts() async {
    final receipts = await DatabaseHelper.instance.getReceipts(
      startDate: _filterStartDate,
      endDate: _filterEndDate,
      minAmount: _filterMinAmount,
      maxAmount: _filterMaxAmount,
    );

    Set<int> years = {DateTime.now().year};
    for (var r in receipts) {
      if (r.date != null) {
        years.add(r.date!.year);
      }
    }
    List<int> sortedYears = years.toList()..sort((a, b) => b.compareTo(a));

    setState(() {
      _allReceipts = receipts;
      _availableYears = sortedYears;
    });
  }

  void _onYearChanged(int year) {
    setState(() {
      _currentDisplayDate = DateTime(year, _currentDisplayDate.month);
    });
  }

  String? _getFilterLabel() {
    List<String> parts = [];
    if (_filterStartDate != null || _filterEndDate != null) {
      String start = _filterStartDate != null ? DateFormat('yyyy/MM/dd').format(_filterStartDate!) : '';
      String end = _filterEndDate != null ? DateFormat('yyyy/MM/dd').format(_filterEndDate!) : '';
      parts.add('$start〜$end');
    }
    if (_filterMinAmount != null || _filterMaxAmount != null) {
      final f = NumberFormat("#,###");
      String min = _filterMinAmount != null ? '¥${f.format(_filterMinAmount)}' : '';
      String max = _filterMaxAmount != null ? '¥${f.format(_filterMaxAmount)}' : '';
      parts.add('$min〜$max');
    }
    if (parts.isEmpty) return null;
    return parts.join(' / ');
  }

  void _showSearchModal() {
    final minController = TextEditingController(text: _filterMinAmount?.toString() ?? '');
    final maxController = TextEditingController(text: _filterMaxAmount?.toString() ?? '');
    DateTime? tempStart = _filterStartDate;
    DateTime? tempEnd = _filterEndDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('検索フィルター', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('日付範囲', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            await DatePickerUtil.showJapaneseDatePicker(context, tempStart, (newDate) {
                              setModalState(() {
                                tempStart = newDate;
                                if (tempEnd != null && tempEnd!.isBefore(newDate)) {
                                  tempEnd = newDate;
                                }
                              });
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4), color: Colors.white),
                            alignment: Alignment.center,
                            child: Text(tempStart != null ? DateFormat('yyyy/MM/dd').format(tempStart!) : '開始日', style: TextStyle(color: tempStart != null ? Colors.black : Colors.grey, fontSize: 16)),
                          ),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text('〜', style: TextStyle(fontSize: 20))),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            await DatePickerUtil.showJapaneseDatePicker(context, tempEnd, (newDate) {
                              setModalState(() => tempEnd = newDate);
                            }, minDate: tempStart);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4), color: Colors.white),
                            alignment: Alignment.center,
                            child: Text(tempEnd != null ? DateFormat('yyyy/MM/dd').format(tempEnd!) : '終了日', style: TextStyle(color: tempEnd != null ? Colors.black : Colors.grey, fontSize: 16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('金額範囲', style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(children: [Expanded(child: TextField(controller: minController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '最小', suffixText: '円'))), const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text('〜')), Expanded(child: TextField(controller: maxController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '最大', suffixText: '円')))]),
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () { setState(() { _filterStartDate = null; _filterEndDate = null; _filterMinAmount = null; _filterMaxAmount = null; }); _loadReceipts(); Navigator.pop(context); }, child: const Text('クリア')),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: () { setState(() { _filterStartDate = tempStart; _filterEndDate = tempEnd; _filterMinAmount = int.tryParse(minController.text); _filterMaxAmount = int.tryParse(maxController.text); }); _loadReceipts(); Navigator.pop(context); }, child: const Text('検索')),
                  ]),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _performOcr(String imagePath) async {
    setState(() => _isProcessing = true);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final receiptData = _parser.parse(recognizedText);
      receiptData.imagePath = imagePath;

      if (receiptData.tel != null && receiptData.tel!.isNotEmpty) {
        final knownStoreName = await DatabaseHelper.instance.getStoreNameByTel(receiptData.tel!);
        if (knownStoreName != null && knownStoreName.isNotEmpty) {
          receiptData.storeName = knownStoreName;
        }
      }

      if (receiptData.amount != null && receiptData.amount! > 0) {
        int total = receiptData.amount!;
        if (receiptData.taxAmount10 != null) {
          double rate = receiptData.taxAmount10! / total;
          if (rate < 0.05 || rate > 0.15) receiptData.taxAmount10 = null;
        }
        if (receiptData.taxAmount8 != null) {
          double rate = receiptData.taxAmount8! / total;
          if (rate < 0.04 || rate > 0.12) receiptData.taxAmount8 = null;
        }
        bool hasTaxInfo = receiptData.targetAmount10 != null ||
            receiptData.taxAmount10 != null ||
            receiptData.targetAmount8 != null ||
            receiptData.taxAmount8 != null;
        if (!hasTaxInfo) {
          int tax = (total * 10 / 110).floor();
          int target = total - tax;
          receiptData.taxAmount10 = tax;
          receiptData.targetAmount10 = target;
        }
      }

      if (!mounted) return;

      List<String> qualityWarnings = [];
      if (receiptData.amount == null) qualityWarnings.add('・合計金額が読み取れませんでした');
      else if (receiptData.amount! > 10000000) qualityWarnings.add('・金額が異常に大きいです (${receiptData.amountFormatted}円)');

      if (receiptData.date == null) qualityWarnings.add('・日付が読み取れませんでした');
      else {
        final now = DateTime.now();
        if (receiptData.date!.isAfter(now.add(const Duration(days: 1)))) qualityWarnings.add('・日付が未来になっています (${receiptData.dateString})');
        if (receiptData.date!.year < 2000) qualityWarnings.add('・日付が過去すぎます (${receiptData.dateString})');
      }

      if (qualityWarnings.isNotEmpty) {
        if (!mounted) return;
        final shouldRescan = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 8), Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('読み取り精度の確認')))]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('以下の項目が正しく認識されていない可能性があります。'), const SizedBox(height: 12), ...qualityWarnings.map((w) => Text(w, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))), const SizedBox(height: 20), const Text('もう一度撮影し直しますか？', style: TextStyle(fontSize: 14))]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('手動で修正')),
              ElevatedButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.camera_alt), label: const Text('再撮影する'), style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary)),
            ],
          ),
        );
        if (shouldRescan == true) { _startScan(); return; }
      }

      if (receiptData.date != null && receiptData.amount != null) {
        final isDuplicate = await DatabaseHelper.instance.checkDuplicate(receiptData.date!, receiptData.amount!);
        if (isDuplicate) {
          if (!mounted) return;
          final shouldProceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('重複の可能性'),
              content: const Text('同じ日時と金額のレシートが既に登録されています。\n編集に進みますか？'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('編集する', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          );
          if (shouldProceed != true) return;
        }
      }

      final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => EditReceiptScreen(initialData: receiptData)));
      if (result == true) {
        await _loadReceipts();
        if (receiptData.date != null) {
          setState(() {
            _currentDisplayDate = receiptData.date!;
            _tabController.animateTo(receiptData.date!.month - 1);
          });
        }
      } else if (result == 'rescan') {
        _startScan();
      }
    } catch (e) { print('OCR Error: $e'); } finally { if (mounted) setState(() => _isProcessing = false); }
  }

  Future<void> _startScan() async {
    try {
      if (_documentScanner == null) return;
      final result = await _documentScanner!.scanDocument();
      if (result.images.isNotEmpty) await _performOcr(result.images.first);
    } catch (e) { print('Scan error: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      drawer: const AppDrawer(), // 追加: ドロワーを設定
      appBar: AppBar(
        backgroundColor: colorScheme.inversePrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('レシート帳'),
            if (_getFilterLabel() != null)
              Text(
                _getFilterLabel()!,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: (_filterStartDate != null || _filterMinAmount != null) ? Colors.red : null),
            onPressed: _showSearchModal,
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: _startScan,
            tooltip: 'レシートをスキャン',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 60,
            width: double.infinity,
            color: colorScheme.surface,
            child: _availableYears.isEmpty
                ? const SizedBox()
                : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              scrollDirection: Axis.horizontal,
              itemCount: _availableYears.length,
              separatorBuilder: (ctx, i) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final year = _availableYears[index];
                final isSelected = year == _currentDisplayDate.year;

                return GestureDetector(
                  onTap: () => _onYearChanged(year),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? colorScheme.primary : Colors.grey[300],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$year年',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            color: colorScheme.surfaceVariant,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: _months.map((m) => Tab(text: '$m月')).toList(),
              labelColor: colorScheme.primary,
              unselectedLabelColor: Colors.grey[700],
              indicatorColor: colorScheme.primary,
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: _months.map((month) {
                    final targetDate = DateTime(_currentDisplayDate.year, month);
                    return _buildReceiptListForMonth(targetDate);
                  }).toList(),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black45,
                    child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除の確認'),
        content: const Text('このレシートを削除してもよろしいですか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('削除する', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (shouldDelete == true) {
      _deleteReceipt(id);
    }
  }

  Widget _buildReceiptListForMonth(DateTime date) {
    final monthlyItems = _allReceipts.where((r) {
      if (r.date == null) return false;
      return r.date!.year == date.year && r.date!.month == date.month;
    }).toList();

    if (monthlyItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text('レシートはありません', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20, top: 8),
      itemCount: monthlyItems.length,
      itemBuilder: (context, index) {
        final item = monthlyItems[index];
        return Slidable(
          key: Key(item.id),
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: 0.25,
            children: [
              SlidableAction(onPressed: (context) => _confirmDelete(context, item.id), backgroundColor: Colors.red, foregroundColor: Colors.white, icon: Icons.delete, label: '削除', borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), bottomLeft: Radius.circular(4))),
            ],
          ),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 2,
            child: ListTile(
              leading: item.imagePath != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(File(item.imagePath!), width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, o, s) => const Icon(Icons.receipt)))
                  : const Icon(Icons.receipt),
              title: Text(item.storeName.isNotEmpty ? item.storeName : '店名なし', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_buildSubtitle(item), style: const TextStyle(fontSize: 12, height: 1.4)),
              trailing: Text('¥${item.amountFormatted}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => EditReceiptScreen(initialData: item, isEditing: true))).then((result) {
                  if (result == true) _loadReceipts();
                });
              },
            ),
          ),
        );
      },
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

  Future<void> _deleteReceipt(String id) async {
    await DatabaseHelper.instance.deleteReceipt(id);
    _loadReceipts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除しました')));
  }

  @override
  void dispose() {
    _documentScanner?.close();
    _textRecognizer.close();
    _tabController.dispose();
    super.dispose();
  }
}