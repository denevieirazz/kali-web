import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';

class BrowserTabItem {
  BrowserTabItem({
    required this.id,
    required this.title,
    required this.url,
  }) : urlController = TextEditingController(text: url);

  final String id;
  String title;
  String url;
  final TextEditingController urlController;
  final WebviewController controller = WebviewController();
  final List<StreamSubscription<Object?>> subscriptions =
      <StreamSubscription<Object?>>[];

  bool initialized = false;
  bool isLoading = true;
  bool canGoBack = false;
  bool canGoForward = false;
  bool disposeRequested = false;
  bool controllerDisposed = false;
  bool _textControllerDisposed = false;
  String? errorMessage;
  Future<void>? _disposeFuture;

  Future<void> disposeControllerIfReady() async {
    if (!initialized || controllerDisposed) return;
    controllerDisposed = true;
    try {
      await controller.dispose();
    } catch (_) {
      // Disposal is best-effort during teardown; the lifecycle flag prevents
      // any later operation from reusing this controller.
    }
  }

  Future<void> dispose() {
    disposeRequested = true;
    return _disposeFuture ??= _disposeInternal();
  }

  Future<void> _disposeInternal() async {
    final activeSubscriptions = List<StreamSubscription<Object?>>.from(
      subscriptions,
    );
    subscriptions.clear();
    for (final subscription in activeSubscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    if (!_textControllerDisposed) {
      _textControllerDisposed = true;
      urlController.dispose();
    }
    await disposeControllerIfReady();
  }
}

class BrowserWindow extends StatefulWidget {
  const BrowserWindow({
    super.key,
    required this.bridge,
    this.initialUrl = 'https://www.google.com',
    this.isVisible = true,
  });

  // Browser traffic is owned exclusively by the WebView2 plugin. The bridge stays
  // in the constructor because all CloudOS windows share the same interface.
  final CloudOSBridge bridge;
  final String initialUrl;
  final bool isVisible;

  @override
  State<BrowserWindow> createState() => _BrowserWindowState();
}

class _BrowserWindowState extends State<BrowserWindow> {
  static const int maxTabs = 24;

  final List<BrowserTabItem> _tabs = <BrowserTabItem>[];
  int _activeTabIndex = 0;
  int _tabCounter = 1;
  bool _isDevToolsOpen = false;

  BrowserTabItem? get _activeTab =>
      _tabs.isNotEmpty && _activeTabIndex < _tabs.length
          ? _tabs[_activeTabIndex]
          : null;

  @override
  void initState() {
    super.initState();
    _addNewTab(widget.initialUrl);
  }

  @override
  void didUpdateWidget(covariant BrowserWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      unawaited(_syncControllerActivity());
    }
  }

  @override
  void dispose() {
    for (final tab in List<BrowserTabItem>.from(_tabs)) {
      // dispose() marks the tab synchronously before its first await, so an
      // in-flight initialize() cannot resurrect a controller after State death.
      unawaited(tab.dispose());
    }
    super.dispose();
  }

  void _addNewTab([String url = 'https://www.google.com']) {
    if (_tabs.length >= maxTabs) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Limite de 24 guias atingido. Feche uma guia antes de abrir outra.',
          ),
        ),
      );
      return;
    }

    final tab = BrowserTabItem(
      id: 'tab_${_tabCounter++}',
      title: 'Nova Guia',
      url: url,
    );
    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });
    unawaited(_initializeTab(tab));
  }

  Future<void> _initializeTab(BrowserTabItem tab) async {
    try {
      final runtimeVersion = await WebviewController.getWebViewVersion();
      if (tab.disposeRequested) return;
      if (runtimeVersion == null) {
        throw StateError('Microsoft Edge WebView2 Runtime não está instalado.');
      }

      await tab.controller.initialize();
      tab.initialized = true;
      if (tab.disposeRequested) {
        await tab.disposeControllerIfReady();
        return;
      }

      await tab.controller.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.sameWindow,
      );
      if (tab.disposeRequested) {
        await tab.disposeControllerIfReady();
        return;
      }

      tab.subscriptions
        ..add(
          tab.controller.url.listen((url) {
            if (!mounted || tab.disposeRequested || !_tabs.contains(tab)) {
              return;
            }
            setState(() {
              tab.url = url;
              tab.urlController.value = TextEditingValue(
                text: url,
                selection: TextSelection.collapsed(offset: url.length),
              );
            });
          }),
        )
        ..add(
          tab.controller.title.listen((title) {
            if (!mounted || tab.disposeRequested || !_tabs.contains(tab)) {
              return;
            }
            setState(
              () => tab.title = title.isEmpty ? 'Navegador Web' : title,
            );
          }),
        )
        ..add(
          tab.controller.loadingState.listen((state) {
            if (!mounted || tab.disposeRequested || !_tabs.contains(tab)) {
              return;
            }
            setState(() => tab.isLoading = state == LoadingState.loading);
          }),
        )
        ..add(
          tab.controller.historyChanged.listen((history) {
            if (!mounted || tab.disposeRequested || !_tabs.contains(tab)) {
              return;
            }
            setState(() {
              tab.canGoBack = history.canGoBack;
              tab.canGoForward = history.canGoForward;
            });
          }),
        )
        ..add(
          tab.controller.onLoadError.listen((error) {
            if (!mounted || tab.disposeRequested || !_tabs.contains(tab)) {
              return;
            }
            setState(() {
              tab.isLoading = false;
              tab.errorMessage = 'Falha de navegação WebView2: ${error.name}';
            });
          }),
        );

      if (tab.disposeRequested) {
        await tab.dispose();
        return;
      }
      await tab.controller.loadUrl(tab.url);
      if (tab.disposeRequested) {
        await tab.dispose();
        return;
      }
      await _syncControllerActivity();
      if (mounted && !tab.disposeRequested && _tabs.contains(tab)) {
        setState(() {
          tab.isLoading = false;
          tab.errorMessage = null;
        });
      }
    } catch (error, stackTrace) {
      if (tab.disposeRequested) {
        await tab.disposeControllerIfReady();
        return;
      }
      CloudOSLogger.error(
        'BrowserWindow',
        'initializeWebView2',
        error,
        stackTrace,
      );
      if (mounted && _tabs.contains(tab)) {
        setState(() {
          tab.isLoading = false;
          tab.errorMessage = error.toString();
        });
      }
    }
  }

  Future<void> _syncControllerActivity() async {
    for (var index = 0; index < _tabs.length; index++) {
      final tab = _tabs[index];
      if (!tab.initialized || tab.disposeRequested || tab.controllerDisposed) {
        continue;
      }
      try {
        if (widget.isVisible && index == _activeTabIndex) {
          await tab.controller.resume();
        } else {
          await tab.controller.suspend();
        }
      } catch (error, stackTrace) {
        if (tab.disposeRequested) continue;
        CloudOSLogger.error(
          'BrowserWindow',
          'syncWebView2Activity',
          error,
          stackTrace,
        );
      }
    }
  }

  void _selectTab(int index) {
    if (index == _activeTabIndex || index < 0 || index >= _tabs.length) return;
    setState(() => _activeTabIndex = index);
    unawaited(_syncControllerActivity());
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1 || index < 0 || index >= _tabs.length) return;
    final tab = _tabs.removeAt(index);
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    } else if (index < _activeTabIndex) {
      _activeTabIndex--;
    }
    setState(() {});
    unawaited(tab.dispose());
    unawaited(_syncControllerActivity());
  }

  String _normalizeTarget(String input) {
    final value = input.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.contains('.') && !value.contains(' ')) {
      return 'https://$value';
    }
    return 'https://www.google.com/search?q=${Uri.encodeComponent(value)}';
  }

  Future<void> _navigateToUrl(String input) async {
    final tab = _activeTab;
    if (tab == null ||
        input.trim().isEmpty ||
        !tab.initialized ||
        tab.disposeRequested ||
        tab.controllerDisposed) {
      return;
    }
    final target = _normalizeTarget(input);
    setState(() {
      tab.url = target;
      tab.urlController.text = target;
      tab.isLoading = true;
      tab.errorMessage = null;
    });
    try {
      await tab.controller.loadUrl(target);
    } catch (error, stackTrace) {
      if (tab.disposeRequested) return;
      CloudOSLogger.error('BrowserWindow', 'navigate', error, stackTrace);
      if (mounted && _tabs.contains(tab)) {
        setState(() {
          tab.isLoading = false;
          tab.errorMessage = error.toString();
        });
      }
    }
  }

  Future<void> _goBack() async {
    final tab = _activeTab;
    if (tab?.initialized == true &&
        tab?.disposeRequested == false &&
        tab?.controllerDisposed == false &&
        tab!.canGoBack) {
      await tab.controller.goBack();
    }
  }

  Future<void> _goForward() async {
    final tab = _activeTab;
    if (tab?.initialized == true &&
        tab?.disposeRequested == false &&
        tab?.controllerDisposed == false &&
        tab!.canGoForward) {
      await tab.controller.goForward();
    }
  }

  Future<void> _reloadOrStop() async {
    final tab = _activeTab;
    if (tab?.initialized != true ||
        tab?.disposeRequested == true ||
        tab?.controllerDisposed == true) {
      return;
    }
    if (tab!.isLoading) {
      await tab.controller.stop();
    } else {
      await tab.controller.reload();
    }
  }

  Future<void> _toggleDevTools() async {
    final tab = _activeTab;
    if (tab?.initialized != true ||
        tab?.disposeRequested == true ||
        tab?.controllerDisposed == true) {
      return;
    }
    await tab!.controller.openDevTools();
    if (mounted) setState(() => _isDevToolsOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final tab = _activeTab;
    return ColoredBox(
      color: const Color(0xFF0F141C),
      child: Column(
        children: <Widget>[
          _buildTabStrip(),
          _buildNavigationBar(tab),
          Expanded(child: _buildViewport(tab)),
        ],
      ),
    );
  }

  Widget _buildTabStrip() {
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
                final isActive = index == _activeTabIndex;
                return InkWell(
                  onTap: () => _selectTab(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF0F141C)
                          : Colors.transparent,
                      border: Border(
                        right: const BorderSide(color: Color(0xFF30363D)),
                        bottom: isActive
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
                        const Icon(
                          Icons.public_rounded,
                          size: 14,
                          color: Color(0xFF8B949E),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isActive
                                  ? Colors.white
                                  : const Color(0xFF8B949E),
                            ),
                          ),
                        ),
                        if (_tabs.length > 1) ...<Widget>[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _closeTab(index),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                Icons.close_rounded,
                                size: 12,
                                color: Color(0xFF8B949E),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Nova Guia',
            onPressed: _addNewTab,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar(BrowserTabItem? tab) {
    final isSecure = tab?.url.toLowerCase().startsWith('https://') ?? false;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Voltar',
            onPressed: tab?.canGoBack == true ? _goBack : null,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'Avançar',
            onPressed: tab?.canGoForward == true ? _goForward : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          ),
          IconButton(
            tooltip: tab?.isLoading == true ? 'Parar' : 'Recarregar',
            onPressed: tab?.initialized == true ? _reloadOrStop : null,
            icon: Icon(
              tab?.isLoading == true
                  ? Icons.close_rounded
                  : Icons.refresh_rounded,
              size: 18,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Row(
                children: <Widget>[
                  Tooltip(
                    message: isSecure
                        ? 'Conexão HTTPS'
                        : 'Conexão sem HTTPS verificado',
                    child: Icon(
                      isSecure
                          ? Icons.lock_outline_rounded
                          : Icons.warning_amber_rounded,
                      size: 14,
                      color: isSecure
                          ? const Color(0xFF3FB950)
                          : const Color(0xFFE3B341),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: tab?.urlController,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                        border: InputBorder.none,
                        hintText: 'Pesquisar ou digitar URL',
                      ),
                      onSubmitted: _navigateToUrl,
                    ),
                  ),
                  if (tab?.isLoading == true)
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Google',
            onPressed: () => _navigateToUrl('https://www.google.com'),
            icon: const Icon(Icons.search_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'GitHub',
            onPressed: () => _navigateToUrl('https://github.com'),
            icon: const Icon(Icons.hub_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'Ferramentas do Desenvolvedor',
            onPressed: tab?.initialized == true ? _toggleDevTools : null,
            icon: Icon(
              Icons.developer_mode_rounded,
              size: 18,
              color: _isDevToolsOpen
                  ? const Color(0xFF58A6FF)
                  : const Color(0xFF8B949E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewport(BrowserTabItem? tab) {
    if (tab == null) return const SizedBox.shrink();
    if (tab.errorMessage != null) {
      return Center(
        child: SelectableText(
          tab.errorMessage!,
          style: const TextStyle(color: Color(0xFFF85149)),
        ),
      );
    }
    if (!tab.initialized || tab.disposeRequested || tab.controllerDisposed) {
      return const Center(child: CircularProgressIndicator());
    }
    return Webview(tab.controller);
  }
}
