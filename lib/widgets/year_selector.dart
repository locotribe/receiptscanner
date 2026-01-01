// lib/widgets/year_selector.dart
import 'package:flutter/material.dart';

class YearSelector extends StatelessWidget {
  final List<int> availableYears;
  final int currentYear;
  final Function(int) onYearChanged;

  const YearSelector({
    super.key,
    required this.availableYears,
    required this.currentYear,
    required this.onYearChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 60,
      width: double.infinity,
      color: colorScheme.surface,
      child: availableYears.isEmpty
          ? const SizedBox()
          : ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: availableYears.length,
        separatorBuilder: (ctx, i) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final year = availableYears[index];
          final isSelected = year == currentYear;
          return GestureDetector(
            onTap: () => onYearChanged(year),
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
    );
  }
}