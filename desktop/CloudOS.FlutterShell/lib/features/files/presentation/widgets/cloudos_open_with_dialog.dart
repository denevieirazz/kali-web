import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../services/cloudos_bridge.dart';

class CloudOSOpenWithOption {
  const CloudOSOpenWithOption({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
    this.description,
  });

  final String id;
  final String name;
  final String category; // 'cloudos', 'windows', 'wsl'
  final IconData icon;
  final String? description;
}

class CloudOSOpenWithDialog extends StatefulWidget {
  const CloudOSOpenWithDialog({
    required this.filePath,
    required this.bridge,
    this.onOpenExternalWindowsDialog,
    super.key,
  });

  final String filePath;
  final CloudOSBridge bridge;
  final VoidCallback? onOpenExternalWindowsDialog;

  static Future<bool?> show({
    required BuildContext context,
    required String filePath,
    required CloudOSBridge bridge,
    VoidCallback? onOpenExternalWindowsDialog,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => CloudOSOpenWithDialog(
        filePath: filePath,
        bridge: bridge,
        onOpenExternalWindowsDialog: onOpenExternalWindowsDialog,
      ),
    );
  }

  @override
  State<CloudOSOpenWithDialog> createState() => _CloudOSOpenWithDialogState();
}

class _CloudOSOpenWithDialogState extends State<CloudOSOpenWithDialog> {
  String? _selectedAppId;
  bool _alwaysUse = false;
  bool _isLoading = true;
  List<CloudOSOpenWithOption> _options = const [];

  String get _fileName {
    final parts = widget.filePath.split(RegExp(r'[\\/]'));
    return parts.where((s) => s.isNotEmpty).lastOrNull ?? widget.filePath;
  }

  String get _fileExtension {
    final idx = _fileName.lastIndexOf('.');
    if (idx != -1 && idx < _fileName.length - 1) {
      return _fileName.substring(idx).toLowerCase();
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _loadAvailableApps();
  }

  Future<void> _loadAvailableApps() async {
    final ext = _fileExtension;
    final defaultOptions = <CloudOSOpenWithOption>[
      const CloudOSOpenWithOption(
        id: 'notes',
        name: 'CloudOS Notes',
        category: 'cloudos',
        icon: Icons.description_rounded,
        description: 'Editor de notas nativo do CloudOS',
      ),
      const CloudOSOpenWithOption(
        id: 'browser',
        name: 'Navegador Web',
        category: 'cloudos',
        icon: Icons.public_rounded,
        description: 'Navegador integrado CloudOS',
      ),
      const CloudOSOpenWithOption(
        id: 'terminal',
        name: 'CloudOS Terminal',
        category: 'cloudos',
        icon: Icons.terminal_rounded,
        description: 'Console PowerShell / WSL',
      ),
      const CloudOSOpenWithOption(
        id: 'windows:notepad',
        name: 'Bloco de Notas (Windows)',
        category: 'windows',
        icon: Icons.edit_note_rounded,
        description: 'Editor de texto padrão do Windows',
      ),
      const CloudOSOpenWithOption(
        id: 'windows:vscode',
        name: 'Visual Studio Code',
        category: 'windows',
        icon: Icons.code_rounded,
        description: 'Editor avançado de código',
      ),
    ];

    if (ext == '.html' || ext == '.htm' || ext == '.svg' || ext == '.pdf') {
      _selectedAppId = 'browser';
    } else if (ext == '.sh' || ext == '.ps1' || ext == '.bat' || ext == '.cmd') {
      _selectedAppId = 'terminal';
    } else {
      _selectedAppId = 'notes';
    }

    if (mounted) {
      setState(() {
        _options = defaultOptions;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleOpen() async {
    if (_selectedAppId == null) return;
    final success = await widget.bridge.openFileWith(
      path: widget.filePath,
      appId: _selectedAppId,
    );
    if (mounted) {
      Navigator.of(context).pop(success);
    }
  }

  void _handleMoreWindowsApps() {
    Navigator.of(context).pop(false);
    if (widget.onOpenExternalWindowsDialog != null) {
      widget.onOpenExternalWindowsDialog!();
    } else {
      widget.bridge.showOpenWithDialog(widget.filePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF131A27),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: CloudOSColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: CloudOSColors.accentSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.open_in_new_rounded,
                      color: CloudOSColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Abrir com o CloudOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CloudOSColors.caption,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: CloudOSColors.caption,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Escolha um aplicativo para abrir este arquivo:',
                style: TextStyle(
                  color: CloudOSColors.secondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _options.length,
                        itemBuilder: (context, index) {
                          final opt = _options[index];
                          final isSelected = _selectedAppId == opt.id;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() => _selectedAppId = opt.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? CloudOSColors.accentSoft
                                      : const Color(0xFF182030),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? CloudOSColors.accent
                                        : CloudOSColors.border,
                                  ),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF222C40),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(
                                        opt.icon,
                                        size: 18,
                                        color: isSelected
                                            ? CloudOSColors.accent
                                            : Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            opt.name,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                          if (opt.description != null)
                                            Text(
                                              opt.description!,
                                              style: const TextStyle(
                                                color: CloudOSColors.caption,
                                                fontSize: 11,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF222C40),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        opt.category.toUpperCase(),
                                        style: const TextStyle(
                                          color: CloudOSColors.caption,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Checkbox(
                    value: _alwaysUse,
                    activeColor: CloudOSColors.accent,
                    onChanged: (val) => setState(() => _alwaysUse = val ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      'Sempre usar este aplicativo para arquivos ',
                      style: TextStyle(
                        color: CloudOSColors.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  TextButton.icon(
                    icon: const Icon(Icons.apps_rounded, size: 15),
                    label: const Text('Mais aplicativos do Windows...'),
                    style: TextButton.styleFrom(
                      foregroundColor: CloudOSColors.caption,
                      textStyle: const TextStyle(fontSize: 11.5),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _handleMoreWindowsApps,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CloudOSColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _selectedAppId != null ? _handleOpen : null,
                    child: const Text('Abrir'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
