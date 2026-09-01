import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../domain/start_app_filter.dart';

class StartFilterBar extends StatelessWidget {
  const StartFilterBar({
    required this.selectedFilter,
    required this.onSelected,
    super.key,
  });

  final String selectedFilter;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: startFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final filter = startFilters[index];
          final isSelected = filter == selectedFilter;
          return InkWell(
            onTap: () => onSelected(filter),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? CloudOSColors.accentSoft
                    : CloudOSColors.elevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? CloudOSColors.accent : CloudOSColors.border,
                ),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  color: isSelected
                      ? CloudOSColors.text
                      : CloudOSColors.secondary,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
