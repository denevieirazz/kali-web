import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../domain/start_app_filter.dart';

class StartFilterBar extends StatelessWidget {
  const StartFilterBar({
    required this.selectedFilter,
    required this.onSelected,
    required this.runningCount,
    super.key,
  });

  final String selectedFilter;
  final ValueChanged<String> onSelected;
  final int runningCount;

  @override
  Widget build(BuildContext context) {
    final primaryAccent = Theme.of(context).colorScheme.primary;
    final primaryAccentSoft = primaryAccent.withValues(alpha: 0.22);

    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (int index = 0; index < startFilters.length; index++) ...<Widget>[
              if (index > 0) const SizedBox(width: 6),
              () {
                final filter = startFilters[index];
                final isSelected = filter == selectedFilter;
                return InkWell(
                  key: ValueKey<String>('start-filter-$filter'),
                  onTap: () => onSelected(filter),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primaryAccentSoft
                          : CloudOSColors.elevated.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? primaryAccent
                            : CloudOSColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          filter,
                          style: TextStyle(
                            color: isSelected
                                ? CloudOSColors.text
                                : CloudOSColors.secondary,
                            fontSize: 11.5,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        if (filter == 'Abertos') ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            key: const ValueKey<String>('start-running-count'),
                            constraints: const BoxConstraints(minWidth: 18),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: runningCount > 0
                                  ? primaryAccent.withValues(alpha: 0.28)
                                  : CloudOSColors.border,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              '$runningCount',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: runningCount > 0
                                    ? primaryAccent
                                    : CloudOSColors.caption,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }(),
            ],
          ],
        ),
      ),
    );
  }
}
