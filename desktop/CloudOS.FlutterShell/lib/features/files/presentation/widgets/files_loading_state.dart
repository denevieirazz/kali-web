import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class FilesLoadingState extends StatelessWidget {
  const FilesLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.folder_open_rounded,
            size: 34,
            color: CloudOSColors.secondary,
          ),
          SizedBox(height: 10),
          Text(
            'Carregando arquivos…',
            style: TextStyle(
              color: CloudOSColors.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
