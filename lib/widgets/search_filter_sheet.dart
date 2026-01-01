// lib/widgets/search_filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/date_picker_util.dart';

class SearchFilterSheet extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final int? initialMinAmount;
  final int? initialMaxAmount;

  const SearchFilterSheet({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
    this.initialMinAmount,
    this.initialMaxAmount,
  });

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  late TextEditingController _minController;
  late TextEditingController _maxController;
  DateTime? _tempStart;
  DateTime? _tempEnd;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(text: widget.initialMinAmount?.toString() ?? '');
    _maxController = TextEditingController(text: widget.initialMaxAmount?.toString() ?? '');
    _tempStart = widget.initialStartDate;
    _tempEnd = widget.initialEndDate;
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    await DatePickerUtil.showJapaneseDatePicker(context, _tempStart, (newDate) {
                      setState(() {
                        _tempStart = newDate;
                        if (_tempEnd != null && _tempEnd!.isBefore(newDate)) {
                          _tempEnd = newDate;
                        }
                      });
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4), color: Colors.white),
                    alignment: Alignment.center,
                    child: Text(_tempStart != null ? DateFormat('yyyy/MM/dd').format(_tempStart!) : '開始日', style: TextStyle(color: _tempStart != null ? Colors.black : Colors.grey, fontSize: 16)),
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text('〜', style: TextStyle(fontSize: 20))),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    await DatePickerUtil.showJapaneseDatePicker(context, _tempEnd, (newDate) {
                      setState(() => _tempEnd = newDate);
                    }, minDate: _tempStart);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4), color: Colors.white),
                    alignment: Alignment.center,
                    child: Text(_tempEnd != null ? DateFormat('yyyy/MM/dd').format(_tempEnd!) : '終了日', style: TextStyle(color: _tempEnd != null ? Colors.black : Colors.grey, fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          const Text('金額範囲', style: TextStyle(fontWeight: FontWeight.bold)),
          Row(children: [Expanded(child: TextField(controller: _minController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '最小', suffixText: '円'))), const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text('〜')), Expanded(child: TextField(controller: _maxController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '最大', suffixText: '円')))]),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, {'clear': true});
              },
              child: const Text('クリア'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'startDate': _tempStart,
                  'endDate': _tempEnd,
                  'minAmount': int.tryParse(_minController.text),
                  'maxAmount': int.tryParse(_maxController.text),
                });
              },
              child: const Text('検索'),
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}