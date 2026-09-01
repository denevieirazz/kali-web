import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class StartSearchField extends StatelessWidget {
  const StartSearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 20,
          color: CloudOSColors.secondary,
        ),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 16),
                onPressed: onClear,
              )
            : null,
        hintText: 'Pesquisar apps, arquivos, comandos e WSL...',
        isDense: true,
      ),
    );
  }
}
