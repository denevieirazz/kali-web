import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../services/cloudos_bridge.dart';
import '../../../services/cloudos_logger.dart';
import '../domain/wsl_runtime_policy.dart';

enum TerminalShellKind { powershell, cmd, wsl }

class TerminalTabItem {
  TerminalTabItem({
    required this.id,
    required this.title,
    required this.shellKind,
    this.distro = '',
  }) : terminal = Terminal(
         maxLines: 5000,
         platform: TerminalTargetPlatform.windows,
       );

  final String id;
  String title;
  final TerminalShellKind shellKind;
  final String distro;
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
    this.bridge = const CloudOSBridge(),
    this.initialDistro,
    this.initialShell = TerminalShellKind.powershell,
  });

  final CloudOSBridge bridge;
  final String? initialDistro;
  final TerminalShellKind initialShell;

  @override
  State<TerminalWindow> createState() => _TerminalWindowState();
}

class _TerminalWindowState extends State<TerminalWindow> {
  final List<TerminalTabItem> _tabs = <TerminalTabItem>[];
  int _activeTabIndex = 0;
  int _tabCounter = 1;
  WslRuntimePolicy _wslPolicy = WslRuntimePolicy(
    wslAvailable: false,
    engineAvailable: false,
    installedDistros: const <String>[],
  );
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
    if (widget.initialShell != TerminalShellKind.wsl) {
      _createInitialTab();
    }
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final snapshot = await widget.bridge.loadSystemSnapshot();
      _wslPolicy = WslRuntimePolicy(
        wslAvailable: snapshot.wslAvailable,
        engineAvailable: snapshot.wslEngineAvailable,
        installedDistros: snapshot.distros,
        defaultDistro: snapshot.defaultDistro,
      );
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'TerminalWindow',
        'loadWslDistros',
        error,
        stackTrace,
      );
    }
    if (mounted && widget.initialShell == TerminalShellKind.wsl) {
      _createInitialTab();
    }
    if (mounted) setState(() {});
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
    if (widget.initialShell == TerminalShellKind.wsl) {
      final requested = widget.initialDistro?.trim() ?? '';
      if (requested.isNotEmpty && !_wslPolicy.containsDistro(requested)) {
        _addUnavailableWslTab(
          title: 'WSL: $requested',
          message:
              'A distribuição "$requested" não está instalada ou não foi detectada pelo System Broker.',
        );
        return;
      }
      final distro = _wslPolicy.resolveRequestedDistro(widget.initialDistro);
      if (!_wslPolicy.canStartWslSession || distro.isEmpty) {
        _addUnavailableWslTab(
          title: 'WSL indisponível',
          message: _wslUnavailableMessage(),
        );
        return;
      }
      _addNewTab(TerminalShellKind.wsl, distro: distro);
      return;
    }
    _addNewTab(widget.initialShell);
  }

  String _titleFor(TerminalShellKind kind, String distro) {
    switch (kind) {
      case TerminalShellKind.cmd:
        return 'CMD (ConPTY)';
      case TerminalShellKind.wsl:
        return distro.isEmpty ? 'WSL (ConPTY)' : 'WSL: $distro';
      case TerminalShellKind.powershell:
        return 'PowerShell (ConPTY)';
    }
  }

  String _wslUnavailableMessage() {
    if (!_wslPolicy.engineAvailable) {
      return 'O mecanismo WSL não foi detectado neste Windows. O CloudOS não iniciará uma sessão Linux falsa.';
    }
    if (!_wslPolicy.hasInstalledDistros) {
      return 'O mecanismo WSL foi detectado, mas nenhuma distribuição Linux registrada foi encontrada. Instale ou provisione uma distribuição antes de abrir esta sessão.';
    }
    return 'Há uma distribuição registrada, mas o runtime ainda não foi confirmado como utilizável. Ela pode exigir provisionamento inicial.';
  }

  void _addUnavailableWslTab({required String title, required String message}) {
    final tab = TerminalTabItem(
      id: 'tab_${_tabCounter++}',
      title: title,
      shellKind: TerminalShellKind.wsl,
    );
    tab.terminal.write('\x1b[33mCloudOS Linux Runtime\x1b[0m\r\n\r\n');
    tab.terminal.write('$message\r\n');
    tab.terminal.write(
      '\r\nStatus: WSL_ENGINE=${_wslPolicy.engineAvailable} | WSL_USABLE=${_wslPolicy.wslAvailable} | DISTROS=${_wslPolicy.installedDistros.length}\r\n',
    );
    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });
  }

  void _addNewTab(TerminalShellKind kind, {String distro = ''}) {
    if (kind == TerminalShellKind.wsl) {
      if (!_wslPolicy.canStartWslSession) {
        _addUnavailableWslTab(
          title: 'WSL indisponível',
          message: _wslUnavailableMessage(),
        );
        return;
      }
      final resolved = _wslPolicy.resolveRequestedDistro(distro);
      if (resolved.isEmpty) {
        _addUnavailableWslTab(
          title: 'WSL indisponível',
          message: _wslUnavailableMessage(),
        );
        return;
      }
      distro = resolved;
    }

    final tab = TerminalTabItem(
      id: 'tab_${_tabCounter++}',
      title: _titleFor(kind, distro),
      shellKind: kind,
      distro: distro,
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
        if (tab.shellKind == TerminalShellKind.wsl) {
          tab.terminal.write(
            '\x1b[33mA distro ${tab.distro.isEmpty ? "WSL padrão" : tab.distro} pode exigir provisionamento inicial ou estar indisponível.\x1b[0m\r\n',
          );
        }
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
    final securityDistro = _wslPolicy.preferredSecurityDistro;
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
                        Icon(
                          item.shellKind == TerminalShellKind.wsl
                              ? Icons.developer_board_rounded
                              : Icons.terminal_rounded,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Text(
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
              } else if (value == 'wsl_unavailable') {
                _addUnavailableWslTab(
                  title: 'WSL indisponível',
                  message: _wslUnavailableMessage(),
                );
              } else if (value == 'wsl_default') {
                _addNewTab(
                  TerminalShellKind.wsl,
                  distro: _wslPolicy.defaultDistro,
                );
              } else if (value.startsWith('wsl:')) {
                _addNewTab(TerminalShellKind.wsl, distro: value.substring(4));
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
              const PopupMenuDivider(),
              if (!_wslPolicy.canStartWslSession)
                PopupMenuItem(
                  value: 'wsl_unavailable',
                  child: Text(
                    !_wslPolicy.engineAvailable
                        ? 'WSL não instalado/detectado'
                        : !_wslPolicy.hasInstalledDistros
                        ? 'WSL sem distribuições detectadas'
                        : 'WSL ainda não utilizável',
                  ),
                )
              else ...<PopupMenuEntry<String>>[
                if (_wslPolicy.defaultDistro.isNotEmpty)
                  PopupMenuItem(
                    value: 'wsl_default',
                    child: Text('WSL padrão: ${_wslPolicy.defaultDistro}'),
                  ),
                for (final distro in _wslPolicy.installedDistros)
                  if (distro != _wslPolicy.defaultDistro)
                    PopupMenuItem(
                      value: 'wsl:$distro',
                      child: Text(_wslPolicy.statusLabelFor(distro)),
                    ),
                if (securityDistro.isEmpty)
                  const PopupMenuItem<String>(
                    enabled: false,
                    child: Text('Kali Linux: não instalada'),
                  ),
              ],
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
