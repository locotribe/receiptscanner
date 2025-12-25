import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class DatePickerUtil {
  static Future<void> showJapaneseDatePicker(
      BuildContext context,
      DateTime? initialDate,
      Function(DateTime) onConfirm, {
        DateTime? minDate,
      }) async {
    final DateTime maxDate = DateTime.now();
    DateTime current = initialDate ?? DateTime.now();
    if (minDate != null && current.isBefore(minDate)) current = minDate;
    if (current.isAfter(maxDate)) current = maxDate;

    int selectedYear = current.year;
    int selectedMonth = current.month;
    int selectedDay = current.day;

    final int minYear = minDate?.year ?? 2000;
    final int maxYear = maxDate.year;

    int getStartMonth(int year) =>
        (minDate != null && year == minDate.year) ? minDate.month : 1;
    int getEndMonth(int year) => (year == maxDate.year) ? maxDate.month : 12;
    int getStartDay(int year, int month) =>
        (minDate != null && year == minDate.year && month == minDate.month)
            ? minDate.day
            : 1;
    int getDaysInMonth(int year, int month) {
      if (month == 2) {
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0) ? 29 : 28;
      }
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

    final yearController =
    FixedExtentScrollController(initialItem: selectedYear - minYear);
    final monthController = FixedExtentScrollController(
        initialItem: selectedMonth - getStartMonth(selectedYear));
    final dayController = FixedExtentScrollController(
        initialItem: selectedDay - getStartDay(selectedYear, selectedMonth));

    await showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            final startMonth = getStartMonth(selectedYear);
            final endMonth = getEndMonth(selectedYear);
            final startDay = getStartDay(selectedYear, selectedMonth);
            final endDay = getEndDay(selectedYear, selectedMonth);

            return Container(
              height: 300,
              color: Colors.white,
              child: Column(
                children: [
                  Container(
                    height: 45,
                    color: Colors.grey[200],
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("キャンセル",
                                style: TextStyle(color: Colors.grey))),
                        TextButton(
                            onPressed: () {
                              onConfirm(DateTime(
                                  selectedYear, selectedMonth, selectedDay));
                              Navigator.pop(context);
                            },
                            child: const Text("完了",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16))),
                      ],
                    ),
                  ),
                  Expanded(
                      child: Row(children: [
                        Expanded(
                            child: CupertinoPicker(
                                scrollController: yearController,
                                itemExtent: 32,
                                onSelectedItemChanged: (i) {
                                  setState(() {
                                    selectedYear = minYear + i;
                                    final newStartMonth = getStartMonth(selectedYear);
                                    final newEndMonth = getEndMonth(selectedYear);
                                    if (selectedMonth < newStartMonth)
                                      selectedMonth = newStartMonth;
                                    if (selectedMonth > newEndMonth)
                                      selectedMonth = newEndMonth;
                                    monthController
                                        .jumpToItem(selectedMonth - newStartMonth);
                                    final newStartDay =
                                    getStartDay(selectedYear, selectedMonth);
                                    final newEndDay =
                                    getEndDay(selectedYear, selectedMonth);
                                    if (selectedDay < newStartDay)
                                      selectedDay = newStartDay;
                                    if (selectedDay > newEndDay)
                                      selectedDay = newEndDay;
                                    dayController.jumpToItem(selectedDay - newStartDay);
                                  });
                                },
                                children: List.generate(
                                    maxYear - minYear + 1,
                                        (i) =>
                                        Center(child: Text("${minYear + i}年"))))),
                        Expanded(
                            child: CupertinoPicker(
                                scrollController: monthController,
                                key: ValueKey('m_$selectedYear'),
                                itemExtent: 32,
                                onSelectedItemChanged: (i) {
                                  setState(() {
                                    final currentStartMonth =
                                    getStartMonth(selectedYear);
                                    selectedMonth = currentStartMonth + i;
                                    final newStartDay =
                                    getStartDay(selectedYear, selectedMonth);
                                    final newEndDay =
                                    getEndDay(selectedYear, selectedMonth);
                                    if (selectedDay < newStartDay)
                                      selectedDay = newStartDay;
                                    if (selectedDay > newEndDay)
                                      selectedDay = newEndDay;
                                    dayController.jumpToItem(selectedDay - newStartDay);
                                  });
                                },
                                children: List.generate(
                                    endMonth - startMonth + 1,
                                        (i) => Center(
                                        child: Text("${startMonth + i}月"))))),
                        Expanded(
                            child: CupertinoPicker(
                                scrollController: dayController,
                                key: ValueKey('d_${selectedYear}_$selectedMonth'),
                                itemExtent: 32,
                                onSelectedItemChanged: (i) {
                                  setState(() {
                                    final currentStartDay =
                                    getStartDay(selectedYear, selectedMonth);
                                    selectedDay = currentStartDay + i;
                                  });
                                },
                                children: List.generate(
                                    endDay - startDay + 1,
                                        (i) => Center(
                                        child: Text("${startDay + i}日"))))),
                      ])),
                ],
              ),
            );
          });
        });
  }
}