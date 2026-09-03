import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../../core/cloudos_theme.dart';

/// Real in-process WebView2 content with Flutter window chrome.
class BrowserWindow extends StatefulWidget {
  const BrowserWindow({super.key});

  @override
  State<BrowserWindow> createState() => _BrowserWindowState();
}

class _BrowserWindowState extends State<BrowserWindow> {
  final WebviewController _webview = WebviewController();
  final TextEditingController _urlController = TextEditingController(
    text: 'https://www.google.com',
  );
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _initialized = false;
  bool _isLoading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final version = await WebviewController.getWebViewVersion();
      if (version == null) {
        throw StateError('Microsoft Edge WebView2 Runtime não está instalado.');
      }
      await _webview.initialize();
      await _webview.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
      _initialized = true;
      _subscriptions
        ..add(
          _webview.url.listen((url) {
            if (!mounted) return;
            setState(() {
              _urlController.value = TextEditingValue(
                text: url,
                selection: TextSelection.collapsed(offset: url.length),
              );
            });
          }),
        )
        ..add(
          _webview.loadingState.listen((state) {
            if (mounted) {
              setState(() => _isLoading = state == LoadingState.loading);
            }
          }),
        )
        ..add(
          _webview.historyChanged.listen((history) {
            if (!mounted) return;
            setState(() {
              _canGoBack = history.canGoBack;
              _canGoForward = history.canGoForward;
            });
          }),
        )
        ..add(
          _webview.onLoadError.listen((error) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _error = 'Falha de navegação WebView2: ${error.name}';
            });
          }),
        );
      await _webview.loadUrl(_urlController.text);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString();
      });
    }
  }

  String _normalizeTarget(String input) {
    final value = input.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.contains('.') && !value.contains(' ')) return 'https://$value';
    return 'https://www.google.com/search?q=${Uri.encodeComponent(value)}';
  }

  Future<void> _navigate(String input) async {
    if (!_initialized || input.trim().isEmpty) return;
    final target = _normalizeTarget(input);
    setState(() {
      _error = null;
      _isLoading = true;
      _urlController.text = target;
    });
    try {
      await _webview.loadUrl(target);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _reloadOrStop() async {
    if (!_initialized) return;
    if (_isLoading) {
      await _webview.stop();
    } else {
      await _webview.reload();
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _urlController.dispose();
    if (_initialized) unawaited(_webview.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF10141D),
      child: Column(
        children: <Widget>[
          _buildToolbar(),
          if (_isLoading)
            const LinearProgressIndicator(
              minHeight: 2,
              color: CloudOSColors.accent,
              backgroundColor: Colors.transparent,
            ),
          Expanded(child: _buildViewport()),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: const Color(0xFF1A202C),
      child: Row(
        children: <Widget>[
          _NavButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Voltar',
            onPressed: _canGoBack ? _webview.goBack : null,
          ),
          _NavButton(
            icon: Icons.arrow_forward_rounded,
            tooltip: 'Avançar',
            onPressed: _canGoForward ? _webview.goForward : null,
          ),
          _NavButton(
            icon: _isLoading ? Icons.close_rounded : Icons.refresh_rounded,
            tooltip: _isLoading ? 'Parar' : 'Recarregar',
            onPressed: _initialized ? _reloadOrStop : null,
          ),
          _NavButton(
            icon: Icons.home_rounded,
            tooltip: 'Página Inicial',
            onPressed: _initialized
                ? () => _navigate('https://www.google.com')
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CloudOSColors.border),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.public_rounded,
                    size: 13,
                    color: CloudOSColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      onSubmitted: _navigate,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Pesquisar ou digitar URL',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _NavButton(
            icon: Icons.developer_mode_rounded,
            tooltip: 'Ferramentas do Desenvolvedor',
            onPressed: _initialized ? _webview.openDevTools : null,
          ),
        ],
      ),
    );
  }

  Widget _buildViewport() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFF85149)),
          ),
        ),
      );
    }
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Webview(_webview);
  }

  Widget _buildStatusBar() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF161B22),
      child: Row(
        children: <Widget>[
          Icon(
            _error == null ? Icons.check_circle_outline : Icons.error_outline,
            size: 12,
            color: _error == null
                ? CloudOSColors.success
                : const Color(0xFFF85149),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _initialized
                  ? (_isLoading ? 'Navegando…' : 'WebView2 conectado')
                  : 'Inicializando WebView2…',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                color: CloudOSColors.caption,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18, color: CloudOSColors.secondary),
        onPressed: onPressed,
        splashRadius: 18,
      ),
    );
  }
}
