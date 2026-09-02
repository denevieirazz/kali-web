import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';

enum TerminalShellKind { powershell, cmd, wsl }

class TerminalTabItem {
  TerminalTabItem({
    required this.id,
    required this.title,
    required this.shellKind,
    this.distro = '',
    this.workingDirectory = '',
  }) : terminal = Terminal(
         maxLines: 5000,
         platform: TerminalTargetPlatform.windows,
       );

  final String id;
  String title;
  final TerminalShellKind shellKind;
  final String distro;
  final String workingDirectory;
  final Terminal terminal;
  final FocusNode focusNode = FocusNode();
  String? sessionId;
  bool isRunning = false;
  int cols = 80;
  int rows = 24;

  void dispose() {
    focusNode.dispose();
  }
}

class TerminalWindow extends StatefulWidget {
  const TerminalWindow({
    super.key,
    required this.bridge,
    this.initialDistro,
    this.initialWorkingDirectory,
    this.initialShell = TerminalShellKind.powershell,
  });

  final CloudOSBridge bridge;
  final String? initialDistro;
  final String? initialWorkingDirectory;
  final TerminalShellKind initialShell;

  @override
  State<TerminalWindow> createState() => _TerminalWindowState();
}

class _TerminalWindowState extends State<TerminalWindow> {
  final List<TerminalTabItem> _tabs = <TerminalTabItem>[];
  int _activeTabIndex = 0;
  int _tabCounter = 1;
  List<String> _wslDistros = <String>[];
  String _defaultDistro = '';
  StreamSubscription<TerminalDataEvent>? _dataSub;
  StreamSubscription<TerminalExitEvent>? _exitSub;

  TerminalTabItem? get _activeTab =>
      _tabs.isNotEmpty && _activeTabIndex < _tabs.length
          ? _tabs[_activeTabIndex]
          : null;

  @override
  void initState() {
    super.initState();
    _subscribeNativeStreams();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final snapshot = await widget.bridge.loadSystemSnapshot();
      _wslDistros = snapshot.distros;
      _defaultDistro = snapshot.defaultDistro;
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'TerminalWindow',
        'loadWslDistros',
        error,
        stackTrace,
      );
    }
    if (mounted) {
      _createInitialTab();
    }
  }

  void _subscribeNativeStreams() {
    _dataSub = widget.bridge.terminalDataStream.listen((event) {
      if (!mounted) return;
      for (final tab in _tabs) {
        if (tab.sessionId == event.sessionId) {
          tab.terminal.write(event.data);
          break;
        }
      }
    });

    _exitSub = widget.bridge.terminalExitStream.listen((event) {
      if (!mounted) return;
      for (final tab in _tabs) {
        if (tab.sessionId == event.sessionId) {
          tab.terminal.write(
            '\r\n\x1b[90m[Processo finalizado com código ${event.exitCode}]\x1b[0m\r\n',
          );
          setState(() => tab.isRunning = false);
          break;
        }
      }
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _exitSub?.cancel();
    for (final tab in _tabs) {
      final sessionId = tab.sessionId;
      if (sessionId != null) {
        unawaited(widget.bridge.closeTerminal(sessionId));
      }
      tab.dispose();
    }
    super.dispose();
  }

  void _createInitialTab() {
    final distro = widget.initialShell == TerminalShellKind.wsl
        ? (widget.initialDistro?.isNotEmpty == true
              ? widget.initialDistro!
              : _defaultDistro)
        : '';
    _addNewTab(
      widget.initialShell,
      distro: distro,
      workingDirectory: widget.initialWorkingDirectory?.trim() ?? '',
    );
  }

  String _titleFor(TerminalShellKind kind, String distro) {
    switch (kind) {
      case TerminalShellKind.cmd:
        return 'CMD (ConPTY)';
      case TerminalShellKind.wsl:
        return distro.isEmpty ? 'WSL padrão (ConPTY)' : 'WSL: $distro';
      case TerminalShellKind.powershell:
        return 'PowerShell (ConPTY)';
    }
  }

  void _addNewTab(
    TerminalShellKind kind, {
    String distro = '',
    String? workingDirectory,
  }) {
    final resolvedDistro = kind == TerminalShellKind.wsl && distro.isEmpty
        ? _defaultDistro
        : distro;
    final resolvedWorkingDirectory =
        workingDirectory ?? _activeTab?.workingDirectory ?? '';
    final tab = TerminalTabItem(
      id: 'tab_${_tabCounter++}',
      title: _titleFor(kind, resolvedDistro),
      shellKind: kind,
      distro: resolvedDistro,
      workingDirectory: resolvedWorkingDirectory.trim(),
    );
    _configureTerminal(tab);
    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });
    unawaited(_startConPtySession(tab));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tab.focusNode.requestFocus();
    });
  }

  void _configureTerminal(TerminalTabItem tab) {
    tab.terminal.onOutput = (data) {
      final sessionId = tab.sessionId;
      if (sessionId != null && tab.isRunning) {
        unawaited(widget.bridge.writeTerminal(sessionId, data));
      }
    };
    tab.terminal.onResize = (cols, rows, pixelWidth, pixelHeight) {
      if (cols == tab.cols && rows == tab.rows) return;
      tab.cols = cols;
      tab.rows = rows;
      final sessionId = tab.sessionId;
      if (sessionId != null && tab.isRunning) {
        unawaited(widget.bridge.resizeTerminal(sessionId, cols, rows));
      }
    };
    tab.terminal.onTitleChange = (title) {
      if (!mounted || title.trim().isEmpty || !_tabs.contains(tab)) return;
      setState(() => tab.title = title.trim());
    };
  }

  Future<void> _startConPtySession(TerminalTabItem tab) async {
    final shell = switch (tab.shellKind) {
      TerminalShellKind.cmd => 'cmd',
      TerminalShellKind.wsl => 'wsl',
      TerminalShellKind.powershell => 'powershell',
    };
    try {
      final sessionId = await widget.bridge.createTerminalSession(
        shellKind: shell,
        distro: tab.distro,
        workingDirectory: tab.workingDirectory,
        cols: tab.cols,
        rows: tab.rows,
      );
      if (!mounted || !_tabs.contains(tab)) {
        if (sessionId != null) {
          await widget.bridge.closeTerminal(sessionId);
        }
        return;
      }
      if (sessionId == null || sessionId.isEmpty) {
        tab.terminal.write(
          '\r\n\x1b[31mFalha ao criar a sessão ConPTY nativa.\x1b[0m\r\n',
        );
        return;
      }
      tab.sessionId = sessionId;
      tab.isRunning = true;
      await widget.bridge.resizeTerminal(sessionId, tab.cols, tab.rows);
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'TerminalWindow',
        'startConPtySession',
        error,
        stackTrace,
      );
      tab.terminal.write('\r\n\x1b[31mErro ConPTY: $error\x1b[0m\r\n');
    }
  }

  void _selectTab(int index) {
    setState(() => _activeTabIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tabs[index].focusNode.requestFocus();
    });
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) return;
    final tab = _tabs.removeAt(index);
    final sessionId = tab.sessionId;
    if (sessionId != null) {
      unawaited(widget.bridge.closeTerminal(sessionId));
    }
    tab.dispose();
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    } else if (index < _activeTabIndex) {
      _activeTabIndex--;
    }
    setState(() {});
  }

  void _sendCtrlC() {
    final tab = _activeTab;
    final sessionId = tab?.sessionId;
    if (sessionId != null && tab!.isRunning) {
      unawaited(widget.bridge.signalTerminal(sessionId, 'ctrl_c'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = _activeTab;
    return ColoredBox(
      color: const Color(0xFF0C1017),
      child: Column(
        children: <Widget>[
          _buildTabBar(),
          Expanded(
            child: tab == null
                ? const Center(child: CircularProgressIndicator())
                : TerminalView(
                    tab.terminal,
                    focusNode: tab.focusNode,
                    autofocus: true,
                    autoResize: true,
                    padding: const EdgeInsets.all(10),
                    textStyle: const TerminalStyle(
                      fontFamily: 'Consolas',
                      fontSize: 13,
                      height: 1.2,
                    ),
                    theme: TerminalThemes.defaultTheme,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final item = _tabs[index];
                final active = index == _activeTabIndex;
                final tooltip = item.workingDirectory.isEmpty
                    ? item.title
                    : '${item.title}\n${item.workingDirectory}';
                return InkWell(
                  onTap: () => _selectTab(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF0C1017)
                          : Colors.transparent,
                      border: Border(
                        right: const BorderSide(color: Color(0xFF30363D)),
                        bottom: active
                            ? const BorderSide(
                                color: Color(0xFF58A6FF),
                                width: 2,
                              )
                            : BorderSide.none,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.terminal_rounded, size: 14),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: tooltip,
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: active
                                  ? Colors.white
                                  : const Color(0xFF8B949E),
                            ),
                          ),
                        ),
                        if (_tabs.length > 1) ...<Widget>[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _closeTab(index),
                            child: const Icon(Icons.close_rounded, size: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Nova aba',
            icon: const Icon(Icons.add_rounded, size: 18),
            color: const Color(0xFF1E232B),
            onSelected: (value) {
              if (value == 'powershell') {
                _addNewTab(TerminalShellKind.powershell);
              } else if (value == 'cmd') {
                _addNewTab(TerminalShellKind.cmd);
              } else if (value == 'wsl_default') {
                _addNewTab(
                  TerminalShellKind.wsl,
                  distro: _defaultDistro,
                );
              } else if (value.startsWith('wsl:')) {
                _addNewTab(
                  TerminalShellKind.wsl,
                  distro: value.substring(4),
                );
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem(
                value: 'powershell',
                child: Text('PowerShell (ConPTY)'),
              ),
              const PopupMenuItem(
                value: 'cmd',
                child: Text('Prompt de Comando (ConPTY)'),
              ),
              if (_defaultDistro.isNotEmpty)
                PopupMenuItem(
                  value: 'wsl_default',
                  child: Text('WSL padrão: $_defaultDistro'),
                ),
              for (final distro in _wslDistros)
                PopupMenuItem(
                  value: 'wsl:$distro',
                  child: Text('WSL: $distro'),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Interromper (Ctrl+C)',
            onPressed: _sendCtrlC,
            icon: const Icon(
              Icons.stop_circle_outlined,
              size: 17,
              color: Color(0xFFE3B341),
            ),
          ),
        ],
      ),
    );
  }
}
