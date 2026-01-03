// lib/screens/home_screen.dart
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
import '../logic/receipt_validator.dart';
import '../logic/receipt_action_helper.dart';
import '../database/database_helper.dart';
import '../widgets/search_filter_sheet.dart';
import '../widgets/receipt_list_item.dart';
import '../widgets/year_selector.dart';
import 'edit_receipt_screen.dart';
import '../logic/auth_service.dart';
import 'components/app_drawer.dart';
import '../logic/google_drive_service.dart';

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
  bool _isSyncing = false; // 同期中フラグ

  List<ReceiptData> _allReceipts = [];
  List<int> _availableYears = [];
  late DateTime _currentDisplayDate;
  late TabController _tabController;

  final List<int> _months = List.generate(12, (index) => index + 1);

  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  int? _filterMinAmount;
  int? _filterMaxAmount;

  // 複数選択モード用の状態管理
  bool _isSelectionMode = false;
  final Set<String> _selectedItemIds = {};

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

    // ログイン確認後、同期を実行
    AuthService.instance.signInSilently().then((_) {
      if (AuthService.instance.currentUser != null) {
        _runFullSync();
      }
    });
  }

  // 起動時同期処理
  Future<void> _runFullSync() async {
    setState(() => _isSyncing = true);
    try {
      await GoogleDriveService.instance.performFullSync();
      await _loadReceipts(); // 同期後のデータを再読込
    } catch (e) {
      print("Sync Error: $e");
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
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
        pageLimit: 1, // ここは挙動確認後に必要であればlimit解除を検討しますが、一旦現状維持
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
    List<int> sortedYears = years.toList()..sort((a, b) => a.compareTo(b));

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

  // --- 検索モーダル ---
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

  void _showSearchModal() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SearchFilterSheet(
          initialStartDate: _filterStartDate,
          initialEndDate: _filterEndDate,
          initialMinAmount: _filterMinAmount,
          initialMaxAmount: _filterMaxAmount,
        );
      },
    );

    if (result != null) {
      setState(() {
        if (result['clear'] == true) {
          _filterStartDate = null;
          _filterEndDate = null;
          _filterMinAmount = null;
          _filterMaxAmount = null;
        } else {
          _filterStartDate = result['startDate'];
          _filterEndDate = result['endDate'];
          _filterMinAmount = result['minAmount'];
          _filterMaxAmount = result['maxAmount'];
        }
      });
      _loadReceipts();
    }
  }

  // --- OCR / スキャン処理 ---
  Future<void> _performOcr(List<String> imagePaths) async {
    setState(() => _isProcessing = true);
    try {
      final List<RecognizedText> recognizedTexts = [];
      for (final path in imagePaths) {
        final inputImage = InputImage.fromFilePath(path);
        final recognizedText = await _textRecognizer.processImage(inputImage);
        recognizedTexts.add(recognizedText);
      }

      // 【修正】Step 3: パーサーにリスト全体を渡して解析・順序判定を行う
      // Step 2で更新したReceiptParserのparseメソッドを呼び出す
      final receiptData = _parser.parse(recognizedTexts, imagePaths);

      // パーサーによってソートされた画像リストの先頭を、一覧表示用のサムネイル画像として設定
      if (receiptData.sourceImagePaths != null && receiptData.sourceImagePaths!.isNotEmpty) {
        receiptData.imagePath = receiptData.sourceImagePaths!.first;
      } else if (imagePaths.isNotEmpty) {
        receiptData.imagePath = imagePaths.first;
      }

      if (receiptData.tel != null && receiptData.tel!.isNotEmpty) {
        final knownStoreName = await DatabaseHelper.instance.getStoreNameByTel(receiptData.tel!);
        if (knownStoreName != null && knownStoreName.isNotEmpty) {
          receiptData.storeName = knownStoreName;
        }
      }

      // --- 学習データに基づくカテゴリー予測 ---
      // 読み取った生のテキストを基に、過去の入力パターンから最適なカテゴリーを推測する
      final predictedCategory = await DatabaseHelper.instance.predictCategory(receiptData.rawText);
      if (predictedCategory != null && predictedCategory.isNotEmpty) {
        receiptData.description = predictedCategory;
      }

      ReceiptValidator.refineTaxData(receiptData);

      if (!mounted) return;

      final qualityWarnings = ReceiptValidator.getQualityWarnings(receiptData);

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

        if (receiptData.id.isNotEmpty) {
          final savedData = _allReceipts.firstWhere((r) => r.id == receiptData.id, orElse: () => receiptData);
          GoogleDriveService.instance.syncReceiptToCloud(savedData);
        }

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
      if (result.images.isNotEmpty) await _performOcr(result.images);
    } catch (e) { print('Scan error: $e'); }
  }

  Future<void> _uploadReceipt(ReceiptData item) async {
    await ReceiptActionHelper.uploadReceipt(context, item, () {
      _loadReceipts();
    });
  }

  Future<void> _uploadSelectedReceipts() async {
    final selectedItems = _allReceipts.where((r) => _selectedItemIds.contains(r.id)).toList();
    await ReceiptActionHelper.uploadSelectedReceipts(context, selectedItems, () {
      setState(() {
        _isSelectionMode = false;
        _selectedItemIds.clear();
      });
      _loadReceipts();
    });
  }

  Future<void> _deleteSelectedReceipts() async {
    final selectedItems = _allReceipts.where((r) => _selectedItemIds.contains(r.id)).toList();
    await ReceiptActionHelper.deleteSelectedReceipts(context, selectedItems, () {
      setState(() {
        _isSelectionMode = false;
        _selectedItemIds.clear();
      });
      _loadReceipts();
    });
  }

  Future<void> _confirmDelete(BuildContext context, ReceiptData item) async {
    await ReceiptActionHelper.confirmDelete(context, item, () {
      _loadReceipts();
    });
  }

  // --- 選択モード制御 ---
  void _toggleSelectionMode(String id) {
    setState(() { _isSelectionMode = true; _selectedItemIds.add(id); });
  }
  void _toggleItemSelection(String id) {
    setState(() { if (_selectedItemIds.contains(id)) { _selectedItemIds.remove(id); if (_selectedItemIds.isEmpty) _isSelectionMode = false; } else { _selectedItemIds.add(id); } });
  }

  void _selectAllItems() {
    final currentMonthItems = _allReceipts.where((r) => r.date != null && r.date!.year == _currentDisplayDate.year && r.date!.month == _currentDisplayDate.month).toList();
    bool isAllCurrentSelected = currentMonthItems.every((item) => _selectedItemIds.contains(item.id));

    setState(() {
      if (isAllCurrentSelected) {
        for (var item in currentMonthItems) {
          _selectedItemIds.remove(item.id);
        }
        if (_selectedItemIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        for (var item in currentMonthItems) {
          _selectedItemIds.add(item.id);
        }
      }
    });
  }

  // --- UI構築 ---
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: _isSelectionMode ? Colors.grey[800] : colorScheme.inversePrimary,
        foregroundColor: _isSelectionMode ? Colors.white : Colors.black,
        title: _isSelectionMode
            ? Text('${_selectedItemIds.length}件 選択中')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('レシート帳'), if (_getFilterLabel() != null) Text(_getFilterLabel()!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis)]),
        leading: _isSelectionMode ? IconButton(icon: const Icon(Icons.close), onPressed: () { setState(() { _isSelectionMode = false; _selectedItemIds.clear(); }); }) : null,
        actions: _isSelectionMode
            ? [
          IconButton(icon: const Icon(Icons.select_all), onPressed: _selectAllItems),
          IconButton(icon: const Icon(Icons.cloud_upload), onPressed: _uploadSelectedReceipts),
          IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelectedReceipts),
        ]
            : [
          IconButton(icon: Icon(Icons.search, color: (_filterStartDate != null || _filterMinAmount != null) ? Colors.red : null), onPressed: _showSearchModal),
          IconButton(icon: const Icon(Icons.camera_alt), onPressed: _startScan),
        ],
      ),
      body: Column(
        children: [
          if (_isSyncing) const LinearProgressIndicator(),

          YearSelector(
            availableYears: _availableYears,
            currentYear: _currentDisplayDate.year,
            onYearChanged: _onYearChanged,
          ),

          Container(
            color: colorScheme.surfaceVariant,
            child: TabBar(controller: _tabController, isScrollable: true, tabAlignment: TabAlignment.start, tabs: _months.map((m) => Tab(text: '$m月')).toList(), labelColor: colorScheme.primary, unselectedLabelColor: Colors.grey[700], indicatorColor: colorScheme.primary),
          ),
          Expanded(
            child: Stack(
              children: [
                TabBarView(controller: _tabController, children: _months.map((month) {
                  final targetDate = DateTime(_currentDisplayDate.year, month);
                  return _buildReceiptListForMonth(targetDate);
                }).toList()),
                if (_isProcessing) Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptListForMonth(DateTime date) {
    final monthlyItems = _allReceipts.where((r) {
      if (r.date == null) return false;
      return r.date!.year == date.year && r.date!.month == date.month;
    }).toList();

    final totalAmount = monthlyItems.fold(0, (sum, item) => sum + (item.amount ?? 0));
    final formatter = NumberFormat("#,###");

    if (monthlyItems.isEmpty) {
      return Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text('レシートはありません', style: TextStyle(color: Colors.grey))
              ]));
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 20, top: 8),
            itemCount: monthlyItems.length,
            itemBuilder: (context, index) {
              final item = monthlyItems[index];
              final isSelected = _selectedItemIds.contains(item.id);

              return ReceiptListItem(
                item: item,
                isSelectionMode: _isSelectionMode,
                isSelected: isSelected,
                onTap: () async {
                  if (_isSelectionMode) { _toggleItemSelection(item.id); return; }

                  bool fileExists = false;
                  if (item.imagePath != null) {
                    fileExists = File(item.imagePath!).existsSync();
                  }

                  if (fileExists) {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => EditReceiptScreen(initialData: item, isEditing: true))).then((result) { if (result == true) _loadReceipts(); });
                    return;
                  }

                  if (item.isUploaded == 1 && item.driveFileId != null) {
                    final bool? download = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('画像のダウンロード'),
                        content: const Text('このレシート画像は端末から削除されています。\n編集するためにダウンロードしますか？'),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ダウンロード'))],
                      ),
                    );
                    if (download == true) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ダウンロード中...')));
                      final downloadedFile = await GoogleDriveService.instance.downloadFile(item.driveFileId!, item.imagePath!);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      if (downloadedFile != null) {
                        _loadReceipts();
                        Navigator.push(context, MaterialPageRoute(builder: (context) => EditReceiptScreen(initialData: item, isEditing: true))).then((result) { if (result == true) _loadReceipts(); });
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ダウンロードに失敗しました')));
                      }
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('このレシートはまだクラウドに画像がアップロードされていません')));
                  }
                },
                onLongPress: () { if (!_isSelectionMode) _toggleSelectionMode(item.id); },
                onUpload: (context) => _uploadReceipt(item),
                onDelete: (context) => _confirmDelete(context, item),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '合計金額',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '¥${formatter.format(totalAmount)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}