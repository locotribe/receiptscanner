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

  List<ReceiptData> _allReceipts = [];
  List<int> _availableYears = [];
  late DateTime _currentDisplayDate;
  late TabController _tabController;

  final List<int> _months = List.generate(12, (index) => index + 1);

  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  int? _filterMinAmount;
  int? _filterMaxAmount;

  // 【追加】複数選択モード用の状態管理
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

    AuthService.instance.signInSilently();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      final selectedMonth = _months[_tabController.index];
      _currentDisplayDate = DateTime(_currentDisplayDate.year, selectedMonth);
      // 月が変わったら選択モードを解除
      _isSelectionMode = false;
      _selectedItemIds.clear();
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
      _isSelectionMode = false;
      _selectedItemIds.clear();
    });
  }

  // --- 検索モーダル関連 ---
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

  // --- OCR / スキャン処理 ---
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

  // --- アップロード処理 (単体) ---
  Future<void> _uploadReceipt(ReceiptData item) async {
    if (AuthService.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('左上のメニューからGoogleアカウントと連携してください')));
      return;
    }

    if (item.imagePath == null || !File(item.imagePath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('アップロードするファイルが見つかりません')));
      return;
    }

    if (item.date == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日付が設定されていないため保存できません')));
      return;
    }

    // 上書き確認
    if (item.isUploaded == 1 && item.driveFileId != null) {
      final bool? shouldOverwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('上書きの確認'),
          content: const Text('このレシートは既に保存されています。\n古いファイルを削除して上書きしますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('上書きする'),
            ),
          ],
        ),
      );
      if (shouldOverwrite != true) return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Googleドライブへアップロード中...')));

    if (item.isUploaded == 1 && item.driveFileId != null) {
      await GoogleDriveService.instance.deleteFile(item.driveFileId!);
    }

    final file = File(item.imagePath!);
    final fileName = _generateFileName(item);

    final fileId = await GoogleDriveService.instance.uploadFile(file, fileName, item.date!);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (fileId != null) {
      await DatabaseHelper.instance.updateUploadStatus(item.id, fileId);

      setState(() {
        final index = _allReceipts.indexWhere((r) => r.id == item.id);
        if (index != -1) {
          _allReceipts[index].isUploaded = 1;
          _allReceipts[index].driveFileId = fileId;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$fileName」を保存しました')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('アップロードに失敗しました')));
    }
  }

  // --- 【追加】一括アップロード処理 ---
  Future<void> _uploadSelectedReceipts() async {
    if (AuthService.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('左上のメニューからGoogleアカウントと連携してください')));
      return;
    }

    if (_selectedItemIds.isEmpty) return;

    // 対象データの取得
    final selectedItems = _allReceipts.where((r) => _selectedItemIds.contains(r.id)).toList();

    // アップロード済みのファイルが含まれているかチェック
    final hasUploadedItems = selectedItems.any((item) => item.isUploaded == 1 && item.driveFileId != null);

    bool skipUploaded = false; // 既済をスキップするかどうか

    if (hasUploadedItems) {
      // 選択肢: キャンセル / 未保存のみ / 全て上書き
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重複ファイルの確認'),
          content: const Text('選択したレシートの中に、既に保存済みのファイルが含まれています。\nどうしますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'skip'),
              child: const Text('未保存のみ実行'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'overwrite'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('すべて上書き'),
            ),
          ],
        ),
      );

      if (result == 'cancel' || result == null) return;
      if (result == 'skip') skipUploaded = true;
    }

    // 進捗ダイアログの表示
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setState) {
              return const PopScope(
                canPop: false,
                child: AlertDialog(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('アップロード中...'),
                    ],
                  ),
                ),
              );
            }
        );
      },
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

        // 上書きの場合は古いファイルを削除
        if (item.isUploaded == 1 && item.driveFileId != null) {
          await GoogleDriveService.instance.deleteFile(item.driveFileId!);
        }

        final file = File(item.imagePath!);
        final fileName = _generateFileName(item);
        final fileId = await GoogleDriveService.instance.uploadFile(file, fileName, item.date!);

        if (fileId != null) {
          await DatabaseHelper.instance.updateUploadStatus(item.id, fileId);
          successCount++;
          // UI用のリストも更新（ループ中にsetStateは避けるため、後でまとめて更新でもよいが、
          // 処理が長い場合はここで内部データを更新しておくと良い）
          final index = _allReceipts.indexWhere((r) => r.id == item.id);
          if (index != -1) {
            _allReceipts[index].isUploaded = 1;
            _allReceipts[index].driveFileId = fileId;
          }
        } else {
          errorCount++;
        }
      } catch (e) {
        errorCount++;
        print("Upload Loop Error: $e");
      }
    }

    // ダイアログを閉じる
    if (!mounted) return;
    Navigator.pop(context);

    // モード解除
    setState(() {
      _isSelectionMode = false;
      _selectedItemIds.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('完了: 成功 $successCount件 / 失敗 $errorCount件')),
    );
  }

  // 【追加】一括削除処理
  Future<void> _deleteSelectedReceipts() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一括削除'),
        content: Text('選択した${_selectedItemIds.length}件のレシートを削除してもよろしいですか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('削除する')),
        ],
      ),
    );

    if (confirm != true) return;

    for (var id in _selectedItemIds) {
      await DatabaseHelper.instance.deleteReceipt(id);
    }

    await _loadReceipts();
    setState(() {
      _isSelectionMode = false;
      _selectedItemIds.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除しました')));
  }

  // ファイル名生成ヘルパー
  String _generateFileName(ReceiptData item) {
    // フォーマット: 2025_1201_1230_店舗名_1000.jpg
    final datePart = DateFormat('yyyy_MMdd').format(item.date!);
    final timePart = DateFormat('HHmm').format(item.date!);

    String safeStoreName = item.storeName.isNotEmpty ? item.storeName : 'NoName';
    safeStoreName = safeStoreName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    final extension = item.imagePath!.split('.').last;
    return "${datePart}_${timePart}_${safeStoreName}_${item.amount ?? 0}.$extension";
  }

  // --- 選択モード制御 ---
  void _toggleSelectionMode(String id) {
    setState(() {
      _isSelectionMode = true;
      _selectedItemIds.add(id);
    });
  }

  void _toggleItemSelection(String id) {
    setState(() {
      if (_selectedItemIds.contains(id)) {
        _selectedItemIds.remove(id);
        if (_selectedItemIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedItemIds.add(id);
      }
    });
  }

  void _selectAllItems() {
    final currentMonthItems = _allReceipts.where((r) {
      return r.date != null &&
          r.date!.year == _currentDisplayDate.year &&
          r.date!.month == _currentDisplayDate.month;
    }).toList();

    setState(() {
      if (_selectedItemIds.length == currentMonthItems.length) {
        // すでに全選択なら解除
        _selectedItemIds.clear();
        _isSelectionMode = false;
      } else {
        // 全選択
        _selectedItemIds.addAll(currentMonthItems.map((e) => e.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: _isSelectionMode ? Colors.grey[800] : colorScheme.inversePrimary,
        foregroundColor: _isSelectionMode ? Colors.white : Colors.black, // 選択モード時は文字を白に
        // 【修正】選択モード時はタイトルを変更
        title: _isSelectionMode
            ? Text('${_selectedItemIds.length}件 選択中')
            : Column(
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
        // 【修正】選択モード時は戻るボタンを「×」にする
        leading: _isSelectionMode
            ? IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() {
              _isSelectionMode = false;
              _selectedItemIds.clear();
            });
          },
        )
            : null, // デフォルトのハンバーガーメニュー等
        actions: _isSelectionMode
            ? [
          // 選択モード時のアクション
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: _selectAllItems,
            tooltip: '全選択/解除',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _uploadSelectedReceipts,
            tooltip: '選択した項目を保存',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteSelectedReceipts,
            tooltip: '選択した項目を削除',
          ),
        ]
            : [
          // 通常時のアクション
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
        final isSelected = _selectedItemIds.contains(item.id);

        // 【修正】選択モード時はチェックボックス、通常時はステータスアイコン
        Widget leadingIcon;
        if (_isSelectionMode) {
          leadingIcon = Icon(
            isSelected ? Icons.check_box : Icons.check_box_outline_blank,
            color: isSelected ? Colors.blue : Colors.grey,
            size: 30,
          );
        } else {
          if (item.isUploaded == 1) {
            leadingIcon = const Icon(Icons.check_circle, color: Colors.green, size: 30);
          } else {
            leadingIcon = const Icon(Icons.cloud_upload, color: Colors.grey, size: 30);
          }
        }

        return Slidable(
          key: Key(item.id),
          // 選択モード中はスワイプ操作を無効化する
          enabled: !_isSelectionMode,
          startActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: 0.25,
            children: [
              SlidableAction(
                onPressed: (context) => _uploadReceipt(item),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                icon: Icons.cloud_upload,
                label: '保存',
                borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
              ),
            ],
          ),
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: 0.25,
            children: [
              SlidableAction(
                onPressed: (context) => _confirmDelete(context, item.id),
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                icon: Icons.delete,
                label: '削除',
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), bottomLeft: Radius.circular(4)),
              ),
            ],
          ),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 2,
            // 選択されている場合は背景色を少し変える
            color: isSelected ? Colors.blue.withOpacity(0.1) : null,
            child: ListTile(
              leading: leadingIcon,
              title: Text(item.storeName.isNotEmpty ? item.storeName : '店名なし', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_buildSubtitle(item), style: const TextStyle(fontSize: 12, height: 1.4)),
              trailing: Text('¥${item.amountFormatted}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),

              // 【修正】タップ時の挙動
              onTap: () {
                if (_isSelectionMode) {
                  _toggleItemSelection(item.id);
                } else {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => EditReceiptScreen(initialData: item, isEditing: true))).then((result) {
                    if (result == true) _loadReceipts();
                  });
                }
              },
              // 【追加】長押しで選択モード開始
              onLongPress: () {
                if (!_isSelectionMode) {
                  _toggleSelectionMode(item.id);
                }
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