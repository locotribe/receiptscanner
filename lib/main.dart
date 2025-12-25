import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_slidable/flutter_slidable.dart'; // 【追加】スライド機能用
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:receiptscanner/models/receipt_data.dart';
import 'package:receiptscanner/logic/receipt_parser.dart';
import 'package:receiptscanner/database/database_helper.dart';

void main() {
  runApp(const ReceiptScannerApp());
}

class ReceiptScannerApp extends StatelessWidget {
  const ReceiptScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white70,
        ),
      ),
      home: const ScannerHomeScreen(),
    );
  }
}

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

  // --- Helper Methods ---

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

  // --- UI Components ---

  Future<void> _showJapaneseDatePicker(
      BuildContext context,
      DateTime? initialDate,
      Function(DateTime) onConfirm,
      {DateTime? minDate}
      ) async {
    final DateTime maxDate = DateTime.now();
    DateTime current = initialDate ?? DateTime.now();
    if (minDate != null && current.isBefore(minDate)) current = minDate;
    if (current.isAfter(maxDate)) current = maxDate;

    int selectedYear = current.year;
    int selectedMonth = current.month;
    int selectedDay = current.day;

    final int minYear = minDate?.year ?? 2000;
    final int maxYear = maxDate.year;

    int getStartMonth(int year) => (minDate != null && year == minDate.year) ? minDate.month : 1;
    int getEndMonth(int year) => (year == maxDate.year) ? maxDate.month : 12;
    int getStartDay(int year, int month) => (minDate != null && year == minDate.year && month == minDate.month) ? minDate.day : 1;
    int getDaysInMonth(int year, int month) {
      if (month == 2) return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0) ? 29 : 28;
      const List<int> days = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
      return days[month];
    }
    int getEndDay(int year, int month) {
      int days = getDaysInMonth(year, month);
      if (year == maxDate.year && month == maxDate.month) {
        return maxDate.day < days ? maxDate.day : days;
      }
      return days;
    }

    final yearController = FixedExtentScrollController(initialItem: selectedYear - minYear);
    final monthController = FixedExtentScrollController(initialItem: selectedMonth - getStartMonth(selectedYear));
    final dayController = FixedExtentScrollController(initialItem: selectedDay - getStartDay(selectedYear, selectedMonth));

    await showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            final startMonth = getStartMonth(selectedYear);
            final endMonth = getEndMonth(selectedYear);
            final startDay = getStartDay(selectedYear, selectedMonth);
            final endDay = getEndDay(selectedYear, selectedMonth);

            return Container(
              height: 300, color: Colors.white,
              child: Column(children: [
                Container(height: 45, color: Colors.grey[200], padding: const EdgeInsets.symmetric(horizontal:16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル", style: TextStyle(color: Colors.grey))), TextButton(onPressed: () { onConfirm(DateTime(selectedYear, selectedMonth, selectedDay)); Navigator.pop(context); }, child: const Text("完了", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),],)),
                Expanded(child: Row(children: [
                  Expanded(child: CupertinoPicker(scrollController: yearController, itemExtent: 32, onSelectedItemChanged: (i) { setState(() { selectedYear = minYear + i; final newStartMonth = getStartMonth(selectedYear); final newEndMonth = getEndMonth(selectedYear); if (selectedMonth < newStartMonth) selectedMonth = newStartMonth; if (selectedMonth > newEndMonth) selectedMonth = newEndMonth; monthController.jumpToItem(selectedMonth - newStartMonth); final newStartDay = getStartDay(selectedYear, selectedMonth); final newEndDay = getEndDay(selectedYear, selectedMonth); if (selectedDay < newStartDay) selectedDay = newStartDay; if (selectedDay > newEndDay) selectedDay = newEndDay; dayController.jumpToItem(selectedDay - newStartDay); }); }, children: List.generate(maxYear - minYear + 1, (i) => Center(child: Text("${minYear + i}年"))) )),
                  Expanded(child: CupertinoPicker(scrollController: monthController, key: ValueKey('m_$selectedYear'), itemExtent: 32, onSelectedItemChanged: (i) { setState(() { final currentStartMonth = getStartMonth(selectedYear); selectedMonth = currentStartMonth + i; final newStartDay = getStartDay(selectedYear, selectedMonth); final newEndDay = getEndDay(selectedYear, selectedMonth); if (selectedDay < newStartDay) selectedDay = newStartDay; if (selectedDay > newEndDay) selectedDay = newEndDay; dayController.jumpToItem(selectedDay - newStartDay); }); }, children: List.generate(endMonth - startMonth + 1, (i) => Center(child: Text("${startMonth + i}月"))) )),
                  Expanded(child: CupertinoPicker(scrollController: dayController, key: ValueKey('d_${selectedYear}_$selectedMonth'), itemExtent: 32, onSelectedItemChanged: (i) { setState(() { final currentStartDay = getStartDay(selectedYear, selectedMonth); selectedDay = currentStartDay + i; }); }, children: List.generate(endDay - startDay + 1, (i) => Center(child: Text("${startDay + i}日"))) )),
                ])),
              ]),
            );
          });
        }
    );
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
                            await _showJapaneseDatePicker(context, tempStart, (newDate) { setModalState(() { tempStart = newDate; if (tempEnd != null && tempEnd!.isBefore(newDate)) { tempEnd = newDate; } }); });
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
                            await _showJapaneseDatePicker(context, tempEnd, (newDate) { setModalState(() => tempEnd = newDate); }, minDate: tempStart);
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

  // --- OCR Processing ---
  Future<void> _performOcr(String imagePath) async {
    setState(() => _isProcessing = true);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final receiptData = _parser.parse(recognizedText);
      receiptData.imagePath = imagePath;

      if (!mounted) return;

      List<String> qualityWarnings = [];
      if (receiptData.amount == null) qualityWarnings.add('・合計金額が読み取れませんでした');
      else if (receiptData.amount! > 10000000) qualityWarnings.add('・金額が異常に大きいです (${receiptData.amountFormatted}円)');
      else if (receiptData.amount! == 0) qualityWarnings.add('・金額が0円になっています');

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
          // 年選択
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

          // 月選択
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

          // コンテンツ
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

  // 【追加】削除確認ダイアログを表示するメソッド
  Future<void> _confirmDelete(BuildContext context, String id) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除の確認'),
        content: const Text('このレシートを削除してもよろしいですか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), // キャンセル
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), // 削除実行
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除する', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      _deleteReceipt(id);
    }
  }

  // 【修正】リスト表示部分にSlidableを適用
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
        // 【変更】Dismissible -> Slidable
        return Slidable(
          key: Key(item.id),
          // 右側からスライドした時のアクション
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: 0.25, // ボタンの幅割合
            children: [
              SlidableAction(
                onPressed: (context) => _confirmDelete(context, item.id),
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                icon: Icons.delete,
                label: '削除',
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4)
                ),
              ),
            ],
          ),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 2,
            child: ListTile(
              leading: item.imagePath != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(item.imagePath!),
                  width: 50, height: 50, fit: BoxFit.cover,
                  errorBuilder: (c, o, s) => const Icon(Icons.receipt),
                ),
              )
                  : const Icon(Icons.receipt),
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
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue,
                ),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditReceiptScreen(
                      initialData: item,
                      isEditing: true,
                    ),
                  ),
                ).then((result) {
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('削除しました')),
    );
  }

  @override
  void dispose() {
    _documentScanner?.close();
    _textRecognizer.close();
    _tabController.dispose();
    super.dispose();
  }
}

// --- 編集・保存画面 (変更なし) ---
class EditReceiptScreen extends StatefulWidget {
  final ReceiptData initialData;
  final bool isEditing;
  const EditReceiptScreen({super.key, required this.initialData, this.isEditing = false});
  @override
  State<EditReceiptScreen> createState() => _EditReceiptScreenState();
}

class _EditReceiptScreenState extends State<EditReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _storeController, _amountController, _target10Controller, _tax10Controller, _target8Controller, _tax8Controller, _telController, _dateController, _timeController, _invoiceController;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _storeController = TextEditingController(text: d.storeName);
    _amountController = TextEditingController(text: d.amount?.toString() ?? '');
    _target10Controller = TextEditingController(text: d.targetAmount10?.toString() ?? '');
    _tax10Controller = TextEditingController(text: d.taxAmount10?.toString() ?? '');
    _target8Controller = TextEditingController(text: d.targetAmount8?.toString() ?? '');
    _tax8Controller = TextEditingController(text: d.taxAmount8?.toString() ?? '');
    _telController = TextEditingController(text: d.tel);
    _dateController = TextEditingController(text: d.dateString);
    _timeController = TextEditingController(text: d.timeString);
    _invoiceController = TextEditingController(text: d.invoiceNumber);
  }

  @override
  void dispose() {
    _storeController.dispose(); _amountController.dispose(); _target10Controller.dispose(); _tax10Controller.dispose();
    _target8Controller.dispose(); _tax8Controller.dispose(); _telController.dispose(); _dateController.dispose();
    _timeController.dispose(); _invoiceController.dispose(); super.dispose();
  }

  Future<void> _showJapaneseDatePicker(BuildContext context, DateTime? initialDate, Function(DateTime) onConfirm) async {
    DateTime current = initialDate ?? DateTime.now();
    int selectedYear = current.year;
    int selectedMonth = current.month;
    int selectedDay = current.day;
    const int startYear = 2000;
    final yearController = FixedExtentScrollController(initialItem: selectedYear - startYear);
    final monthController = FixedExtentScrollController(initialItem: selectedMonth - 1);
    final dayController = FixedExtentScrollController(initialItem: selectedDay - 1);

    int getDaysInMonth(int year, int month) {
      if (month == 2) return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0) ? 29 : 28;
      const List<int> days = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
      return days[month];
    }

    await showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            int maxDays = getDaysInMonth(selectedYear, selectedMonth);
            return Container(
              height: 300, color: Colors.white,
              child: Column(children: [
                Container(height: 45, color: Colors.grey[200], padding: const EdgeInsets.symmetric(horizontal:16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル", style: TextStyle(color: Colors.grey))), TextButton(onPressed: () { onConfirm(DateTime(selectedYear, selectedMonth, selectedDay)); Navigator.pop(context); }, child: const Text("完了", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),],)),
                Expanded(child: Row(children: [
                  Expanded(child: CupertinoPicker(scrollController: yearController, itemExtent: 32, onSelectedItemChanged: (i) { setState(() { selectedYear = startYear + i; if (selectedDay > getDaysInMonth(selectedYear, selectedMonth)) { selectedDay = getDaysInMonth(selectedYear, selectedMonth); dayController.jumpToItem(selectedDay - 1); } }); }, children: List.generate(101, (i) => Center(child: Text("${startYear + i}年"))))),
                  Expanded(child: CupertinoPicker(scrollController: monthController, itemExtent: 32, onSelectedItemChanged: (i) { setState(() { selectedMonth = 1 + i; if (selectedDay > getDaysInMonth(selectedYear, selectedMonth)) { selectedDay = getDaysInMonth(selectedYear, selectedMonth); dayController.jumpToItem(selectedDay - 1); } }); }, children: List.generate(12, (i) => Center(child: Text("${1 + i}月"))))),
                  Expanded(child: CupertinoPicker(scrollController: dayController, itemExtent: 32, onSelectedItemChanged: (i) { setState(() => selectedDay = 1 + i); }, children: List.generate(maxDays, (i) => Center(child: Text("${1 + i}日"))))),
                ])),
              ]),
            );
          });
        }
    );
  }

  Future<void> _pickDate() async {
    DateTime initial = DateTime.now();
    try { if (_dateController.text.isNotEmpty) initial = DateFormat('yyyy-MM-dd').parse(_dateController.text); } catch (_) {}
    await _showJapaneseDatePicker(context, initial, (newDate) {
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
    if (_formKey.currentState!.validate()) {
      final storeName = _storeController.text;
      final amount = int.tryParse(_amountController.text.replaceAll(',', ''));
      final target10 = int.tryParse(_target10Controller.text.replaceAll(',', ''));
      final tax10 = int.tryParse(_tax10Controller.text.replaceAll(',', ''));
      final target8 = int.tryParse(_target8Controller.text.replaceAll(',', ''));
      final tax8 = int.tryParse(_tax8Controller.text.replaceAll(',', ''));
      final date = _dateController.text;
      final time = _timeController.text;
      final invoice = _invoiceController.text;
      final tel = _telController.text;

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

      String id = widget.initialData.id;
      if (id.isEmpty) { id = '${storeName}_${date.replaceAll('-', '')}${time.replaceAll(':', '')}$amount'; }

      final saveData = ReceiptData(
        id: id, storeName: storeName, date: dateTime, amount: amount,
        targetAmount10: target10, targetAmount8: target8, taxAmount10: tax10, taxAmount8: tax8,
        invoiceNumber: invoice, tel: tel, rawText: widget.initialData.rawText, imagePath: widget.initialData.imagePath,
      );
      await DatabaseHelper.instance.insertReceipt(saveData);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存しました')));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '詳細・編集' : '内容確認'),
        actions: [
          if (!widget.isEditing) IconButton(onPressed: () => Navigator.pop(context, 'rescan'), icon: const Icon(Icons.camera_alt)),
          IconButton(onPressed: _saveData, icon: const Icon(Icons.save)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (widget.initialData.imagePath != null)
                Container(
                  height: 200, width: double.infinity,
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                  child: InteractiveViewer(child: Image.file(File(widget.initialData.imagePath!), fit: BoxFit.contain)),
                ),
              const SizedBox(height: 16),
              TextFormField(controller: _storeController, decoration: const InputDecoration(labelText: '店名', prefixIcon: Icon(Icons.store))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(flex: 3, child: TextFormField(controller: _dateController, decoration: const InputDecoration(labelText: '日付', prefixIcon: Icon(Icons.calendar_today)), readOnly: true, onTap: _pickDate)),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: TextFormField(controller: _timeController, decoration: const InputDecoration(labelText: '時間', prefixIcon: Icon(Icons.access_time)), readOnly: true, onTap: _pickTime)),
              ]),
              const SizedBox(height: 12),
              TextFormField(controller: _amountController, decoration: const InputDecoration(labelText: '合計金額 (税込)', prefixIcon: Icon(Icons.currency_yen)), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              Row(children: [
                const Text('10%', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 16),
                Expanded(child: TextFormField(controller: _target10Controller, decoration: const InputDecoration(labelText: '対象額'), keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(controller: _tax10Controller, decoration: const InputDecoration(labelText: '税額'), keyboardType: TextInputType.number)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Text(' 8%', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 16),
                Expanded(child: TextFormField(controller: _target8Controller, decoration: const InputDecoration(labelText: '対象額'), keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(controller: _tax8Controller, decoration: const InputDecoration(labelText: '税額'), keyboardType: TextInputType.number)),
              ]),
              const SizedBox(height: 12),
              TextFormField(controller: _invoiceController, decoration: const InputDecoration(labelText: 'インボイス登録番号', prefixIcon: Icon(Icons.verified))),
              const SizedBox(height: 12),
              TextFormField(controller: _telController, decoration: const InputDecoration(labelText: '電話番号', prefixIcon: Icon(Icons.phone))),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _saveData, icon: const Icon(Icons.save), label: const Text('保存する'), style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary))),
            ],
          ),
        ),
      ),
    );
  }
}