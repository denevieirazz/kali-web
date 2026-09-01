import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class FilesEmptyState extends StatelessWidget {
  const FilesEmptyState({required this.query, super.key});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.folder_open_rounded,
            size: 44,
            color: CloudOSColors.caption,
          ),
          const SizedBox(height: 10),
          Text(
            query.isNotEmpty
                ? 'Nenhum arquivo correspondente a "$query"'
                : 'Pasta vazia',
            style: const TextStyle(
              color: CloudOSColors.secondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
