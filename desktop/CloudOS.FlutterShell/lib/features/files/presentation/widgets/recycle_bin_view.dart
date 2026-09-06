import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../services/cloudos_bridge.dart';

class RecycleBinItem {
  const RecycleBinItem({
    required this.id,
    required this.name,
    required this.originalPath,
    required this.deletedDate,
    required this.sizeBytes,
    required this.isFolder,
  });

  final String id;
  final String name;
  final String originalPath;
  final DateTime deletedDate;
  final int sizeBytes;
  final bool isFolder;

  String get sizeFormatted {
    if (isFolder) return 'Pasta de arquivos';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get dateFormatted {
    final day = deletedDate.day.toString().padLeft(2, '0');
    final month = deletedDate.month.toString().padLeft(2, '0');
    final year = deletedDate.year;
    final hour = deletedDate.hour.toString().padLeft(2, '0');
    final min = deletedDate.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$min';
  }
}

class RecycleBinView extends StatefulWidget {
  const RecycleBinView({
    super.key,
    required this.bridge,
    this.onBack,
  });

  final CloudOSBridge bridge;
  final VoidCallback? onBack;

  @override
  State<RecycleBinView> createState() => _RecycleBinViewState();
}

class _RecycleBinViewState extends State<RecycleBinView> {
  bool _isLoading = true;
  int _itemCount = 0;
  int _totalSizeBytes = 0;
  final List<RecycleBinItem> _items = <RecycleBinItem>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecycleBin());
  }

  Future<void> _loadRecycleBin() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.bridge.invokeBrokerRpc('files.queryRecycleBin');
      if (mounted) {
        final count = (res?['itemCount'] as num?)?.toInt() ?? 0;
        final size = (res?['totalSizeBytes'] as num?)?.toInt() ?? 0;
        setState(() {
          _itemCount = count;
          _totalSizeBytes = size;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _emptyRecycleBin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141C2B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: CloudOSColors.border),
        ),
        title: const Row(
          children: <Widget>[
            Icon(Icons.delete_forever_rounded, color: CloudOSColors.danger, size: 22),
            SizedBox(width: 10),
            Text('Esvaziar Lixeira', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Tem certeza de que deseja excluir permanentemente todos os itens da Lixeira do CloudOS? '
          'Esta ação não pode ser desfeita.',
          style: TextStyle(color: CloudOSColors.secondary, fontSize: 13),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: CloudOSColors.caption)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CloudOSColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Esvaziar Definitivamente', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await widget.bridge.invokeBrokerRpc('files.emptyRecycleBin');
      } catch (_) {}
      await _loadRecycleBin();
    }
  }

  String _formatTotalSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CloudOSColors.background,
      child: Column(
        children: <Widget>[
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF101726),
              border: Border(bottom: BorderSide(color: CloudOSColors.border)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Row(
                    children: <Widget>[
                      if (widget.onBack != null) ...[
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          color: CloudOSColors.text,
                          tooltip: 'Voltar para Início',
                          onPressed: widget.onBack,
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Icon(Icons.delete_outline_rounded, color: CloudOSColors.danger, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'Lixeira CloudOS',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: CloudOSColors.elevated,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: CloudOSColors.border),
                          ),
                          child: Text(
                            '$_itemCount item(ns) • ${_formatTotalSize(_totalSizeBytes)}',
                            style: const TextStyle(color: CloudOSColors.caption, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text('Atualizar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CloudOSColors.text,
                    side: const BorderSide(color: CloudOSColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: _loadRecycleBin,
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: const Text('Esvaziar Lixeira'),
                  style: FilledButton.styleFrom(
                    backgroundColor: CloudOSColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: _itemCount > 0 ? _emptyRecycleBin : null,
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: CloudOSColors.accent),
                  )
                : _itemCount == 0 && _items.isEmpty
                    ? _buildEmptyState()
                    : _buildItemsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: CloudOSColors.elevated,
              shape: BoxShape.circle,
              border: Border.all(color: CloudOSColors.border),
            ),
            child: const Icon(Icons.delete_outline_rounded, size: 36, color: CloudOSColors.caption),
          ),
          const SizedBox(height: 16),
          const Text(
            'A Lixeira está vazia',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Arquivos e pastas excluídos no CloudOS serão listados aqui.',
            style: TextStyle(color: CloudOSColors.caption, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101726),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: CloudOSColors.border),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.info_outline_rounded, size: 20, color: CloudOSColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'A Lixeira contém $_itemCount item(ns) totalizando ${_formatTotalSize(_totalSizeBytes)}. '
                  'Para recuperar espaço em disco permanentemente, clique em "Esvaziar Lixeira".',
                  style: const TextStyle(color: CloudOSColors.secondary, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
