import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/cloud_system_snapshot.dart';
import '../../../services/cloudos_bridge.dart';

class TerminalWindow extends StatefulWidget {
  const TerminalWindow({
    this.snapshot = CloudOSBridge.degradedSnapshot,
    this.bridge = const CloudOSBridge(),
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final CloudOSBridge bridge;

  @override
  State<TerminalWindow> createState() => _TerminalWindowState();
}

class _TerminalWindowState extends State<TerminalWindow> {
  int _selectedTab = 0;
  final List<String> _tabs = const <String>[
    'PowerShell 7',
    'Prompt de Comando',
    'Ubuntu WSL2',
  ];

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<String> _outputLines = <String>[
    'CloudOS Terminal [Versão 21.0.0-modular]',
    '(c) CloudOS Core. Todos os direitos reservados.',
    'Sessão: ConPTY Host • Backend: System Broker V21',
    '',
    'Digite "help" para ver comandos disponíveis ou execute comandos do sistema.',
    '',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _prompt {
    switch (_selectedTab) {
      case 0:
        return 'PS C:\\CloudOS> ';
      case 1:
        return 'C:\\CloudOS> ';
      case 2:
        return 'douglas@cloudos-ubuntu:~\$ ';
      default:
        return '> ';
    }
  }

  void _handleSubmit(String text) {
    final command = text.trim();
    _inputController.clear();

    setState(() {
      _outputLines.add('$_prompt$command');
      if (command.isEmpty) {
        _scrollToBottom();
        return;
      }

      final lower = command.toLowerCase();
      if (lower == 'clear' || lower == 'cls') {
        _outputLines.clear();
      } else if (lower == 'help') {
        _outputLines.addAll(<String>[
          'Comandos suportados:',
          '  help        - Mostra esta lista de ajuda',
          '  clear, cls  - Limpa a tela do terminal',
          '  whoami      - Exibe o usuário da sessão ativa',
          '  wsl, wsl -l - Mostra distribuições Linux WSL2 ativas',
          '  systeminfo  - Exibe informações do CloudOS V21',
          '  exit        - Encerra a sessão do terminal',
        ]);
      } else if (lower == 'whoami') {
        _outputLines.add('cloudos\\douglas (Administrador)');
      } else if (lower == 'wsl' || lower == 'wsl -l' || lower == 'wsl -l -v') {
        if (widget.snapshot.wslAvailable) {
          _outputLines.add('Distribuições WSL instaladas:');
          for (final distro in widget.snapshot.distros) {
            _outputLines.add('  * $distro (Running, WSL 2)');
          }
        } else {
          _outputLines.add('WSL: Subsistema Linux não inicializado ou indisponível.');
        }
      } else if (lower == 'systeminfo') {
        _outputLines.addAll(<String>[
          'SO: CloudOS V21 Modular Desktop',
          'Dispositivo: ${widget.snapshot.deviceName}',
          'Rede: ${widget.snapshot.networkName} (${widget.snapshot.networkAvailable ? "Conectado" : "Desconectado"})',
          'Área Atual: Workspace ${widget.snapshot.currentWorkspace}',
          'Backend: System Broker V21 (Named Pipe IPC)',
        ]);
      } else {
        _outputLines.add('Comando executado via ConPTY host: "$command"');
      }
      _outputLines.add('');
    });

    _scrollToBottom();
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C1017),
      child: Column(
        children: <Widget>[
          _buildTabBar(),
          Expanded(
            child: GestureDetector(
              onTap: () => _focusNode.requestFocus(),
              behavior: HitTestBehavior.opaque,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _outputLines.length + 1,
                itemBuilder: (context, index) {
                  if (index < _outputLines.length) {
                    return Text(
                      _outputLines[index],
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 13,
                        color: Color(0xFFE2E8F0),
                        height: 1.35,
                      ),
                    );
                  }
                  return _buildInputRow();
                },
              ),
            ),
          ),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 32,
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: List<Widget>.generate(_tabs.length, (index) {
          final isSelected = _selectedTab == index;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedTab = index;
                _outputLines.add('');
                _outputLines.add('--- Alternado para ${_tabs[index]} ---');
                _outputLines.add('');
              });
              _scrollToBottom();
              _focusNode.requestFocus();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0C1017) : Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                border: isSelected
                    ? const Border(
                        top: BorderSide(color: CloudOSColors.accent, width: 2),
                      )
                    : null,
              ),
              child: Text(
                _tabs[index],
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? Colors.white : CloudOSColors.caption,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildInputRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          _prompt,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: _selectedTab == 2 ? CloudOSColors.linux : CloudOSColors.accent,
          ),
        ),
        Expanded(
          child: TextField(
            controller: _inputController,
            focusNode: _focusNode,
            onSubmitted: _handleSubmit,
            cursorColor: CloudOSColors.accent,
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontSize: 13,
              color: Colors.white,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF161B22),
      child: Row(
        children: <Widget>[
          const Icon(Icons.circle, size: 8, color: CloudOSColors.success),
          const SizedBox(width: 6),
          Text(
            'ConPTY / ${_tabs[_selectedTab]}',
            style: const TextStyle(fontSize: 10.5, color: CloudOSColors.caption),
          ),
          const Spacer(),
          const Text(
            'UTF-8  |  Shell Host V21',
            style: TextStyle(fontSize: 10.5, color: CloudOSColors.caption),
          ),
        ],
      ),
    );
  }
}
