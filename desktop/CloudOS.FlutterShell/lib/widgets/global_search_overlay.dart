import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/cloudos_theme.dart';
import '../models/search_models.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';
import '../services/global_search_service.dart';

typedef AppSelectionCallback = void Function(
  String appId, {
  Map<String, dynamic>? params,
});

class GlobalSearchOverlay extends StatefulWidget {
  const GlobalSearchOverlay({
    super.key,
    required this.apps,
    required this.onSelectApp,
    required this.onClose,
    this.bridge = const CloudOSBridge(),
  });

  final List<CloudApp> apps;
  final AppSelectionCallback onSelectApp;
  final VoidCallback onClose;
  final CloudOSBridge bridge;

  @override
  State<GlobalSearchOverlay> createState() => _GlobalSearchOverlayState();
}

class _GlobalSearchOverlayState extends State<GlobalSearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _textFocus = FocusNode(debugLabel: 'global-search-text');
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'global-search-keys');

  late GlobalSearchService _service;
  Timer? _debounce;
  SearchBatch? _batch;
  bool _loading = true;
  String? _error;
  int _selectedIndex = 0;
  int _uiGeneration = 0;

  @override
  void initState() {
    super.initState();
    _service = GlobalSearchService(bridge: widget.bridge);
    unawaited(_runSearch(immediate: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant GlobalSearchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bridge, widget.bridge)) {
      _service.cancel();
      _service = GlobalSearchService(bridge: widget.bridge);
    }
    if (!identical(oldWidget.apps, widget.apps)) {
      _scheduleSearch(const Duration(milliseconds: 40));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _service.cancel();
    _controller.dispose();
    _textFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _scheduleSearch(const Duration(milliseconds: 240));
  }

  void _scheduleSearch(Duration delay) {
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      if (mounted) unawaited(_runSearch());
    });
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
  }

  Future<void> _runSearch({bool immediate = false}) async {
    _debounce?.cancel();
    final generation = ++_uiGeneration;
    if (mounted && !immediate) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final batch = await _service.search(
        rawQuery: _controller.text,
        runtimeApps: widget.apps,
      );
      if (!mounted || generation != _uiGeneration) return;
      setState(() {
        _batch = batch;
        _loading = false;
        _error = null;
        final count = batch.results.length;
        if (count == 0) {
          _selectedIndex = 0;
        } else if (_selectedIndex >= count) {
          _selectedIndex = count - 1;
        }
      });
    } catch (error, stackTrace) {
      CloudOSLogger.error('GlobalSearchOverlay', 'runSearch', error, stackTrace);
      if (!mounted || generation != _uiGeneration) return;
      setState(() {
        _loading = false;
        _error = 'A busca não pôde ser concluída.';
      });
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final results = _batch?.results ?? const <SearchResult>[];
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (results.isNotEmpty) {
        setState(() => _selectedIndex = (_selectedIndex + 1) % results.length);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (results.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + results.length) % results.length;
        });
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home && results.isNotEmpty) {
      setState(() => _selectedIndex = 0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end && results.isNotEmpty) {
      setState(() => _selectedIndex = results.length - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && results.isNotEmpty) {
      unawaited(_activate(results[_selectedIndex]));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _activate(SearchResult result) async {
    if (!result.isAvailable || !result.action.isExecutable) return;
    var success = true;
    try {
      final action = result.action;
      switch (action.kind) {
        case SearchActionKind.openInternalApp:
        case SearchActionKind.openFolder:
        case SearchActionKind.openProject:
        case SearchActionKind.openSettingsPage:
        case SearchActionKind.openWslTerminal:
          final appId = action.appId;
          if (appId == null || appId.isEmpty) {
            success = false;
          } else {
            widget.onClose();
            widget.onSelectApp(
              appId,
              params: action.params.isEmpty ? null : action.params,
            );
          }
          break;
        case SearchActionKind.launchRuntimeApp:
          final id = action.runtimeAppId;
          if (id == null || id.isEmpty) {
            success = false;
          } else {
            success = await widget.bridge.launchApp(id);
            if (success) widget.onClose();
          }
          break;
        case SearchActionKind.openFile:
          final appId = action.appId;
          if (appId != null && appId.isNotEmpty) {
            widget.onClose();
            widget.onSelectApp(
              appId,
              params: action.params.isEmpty ? null : action.params,
            );
          } else {
            final path = action.path;
            if (path == null || path.isEmpty) {
              success = false;
            } else {
              success = await widget.bridge.openDefault(path);
              if (success) widget.onClose();
            }
          }
          break;
        case SearchActionKind.none:
          success = false;
          break;
      }
    } catch (error, stackTrace) {
      success = false;
      CloudOSLogger.error(
        'GlobalSearchOverlay',
        'activate:${result.id}',
        error,
        stackTrace,
      );
    }

    if (success) {
      unawaited(_service.recordActivation(result));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Não foi possível abrir ${result.title}.')),
    );
  }

  void _clearQuery() {
    _controller.clear();
    _selectedIndex = 0;
    _scheduleSearch(Duration.zero);
    _textFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final batch = _batch;
    final results = batch?.results ?? const <SearchResult>[];
    final diagnostics = batch?.diagnostics ?? const SearchDiagnostics.empty();

    return Focus(
      focusNode: _keyboardFocus,
      canRequestFocus: false,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: widget.onClose,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.52),
          alignment: const Alignment(0, -0.34),
          child: GestureDetector(
            onTap: () => _textFocus.requestFocus(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: Container(
                  width: 720,
                  constraints: const BoxConstraints(maxHeight: 590),
                  decoration: BoxDecoration(
                    color: const Color(0xF20E1322),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: CloudOSColors.accent.withValues(alpha: 0.48),
                      width: 1.25,
                    ),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Colors.black87,
                        blurRadius: 44,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildSearchField(),
                      if (_loading) const LinearProgressIndicator(minHeight: 2),
                      Flexible(child: _buildBody(results)),
                      _buildFooter(diagnostics),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.search_rounded,
            size: 23,
            color: CloudOSColors.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _textFocus,
              style: const TextStyle(fontSize: 15, color: Colors.white),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                fillColor: Colors.transparent,
                hintText: 'Buscar apps, arquivos, configurações, projetos e WSL...',
                hintStyle: TextStyle(fontSize: 14, color: Colors.white38),
              ),
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) {
                final results = _batch?.results ?? const <SearchResult>[];
                if (results.isNotEmpty) {
                  unawaited(_activate(results[_selectedIndex]));
                }
              },
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Limpar busca',
              icon: const Icon(Icons.close_rounded, size: 18),
              color: Colors.white60,
              onPressed: _clearQuery,
            ),
        ],
      ),
    );
  }

  Widget _buildBody(List<SearchResult> results) {
    if (_error != null) {
      return _EmptySearchState(
        icon: Icons.error_outline_rounded,
        title: _error!,
        subtitle: 'O restante do CloudOS continua disponível.',
      );
    }
    if (!_loading && results.isEmpty) {
      return const _EmptySearchState(
        icon: Icons.search_off_rounded,
        title: 'Nenhum resultado encontrado',
        subtitle:
            'Tente app:, file:, settings:, project:, wsl: ou ext:pdf para filtrar.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return _SearchResultTile(
          result: result,
          selected: index == _selectedIndex,
          onHover: () {
            if (_selectedIndex != index) {
              setState(() => _selectedIndex = index);
            }
          },
          onTap: () => unawaited(_activate(result)),
        );
      },
    );
  }

  Widget _buildFooter(SearchDiagnostics diagnostics) {
    final parts = <String>[
      '↑↓ navegar',
      'Enter abrir',
      'Esc fechar',
    ];
    if (diagnostics.fileDirectoriesVisited > 0) {
      parts.add('${diagnostics.fileDirectoriesVisited} pastas verificadas');
    }
    if (diagnostics.fileSearchTruncated) {
      parts.add('busca de arquivos limitada');
    }
    if (diagnostics.sourcesFailed.isNotEmpty) {
      parts.add('fonte indisponível: ${diagnostics.sourcesFailed.join(', ')}');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: Text(
        parts.join('  •  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10.5,
          color: Colors.white38,
          fontFamily: 'Consolas',
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final SearchResult result;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: result.isAvailable ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? CloudOSColors.accent.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(
                    color: CloudOSColors.accent.withValues(alpha: 0.28),
                  )
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: result.iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(result.icon, size: 20, color: result.iconColor),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            result.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: result.isAvailable
                                  ? Colors.white
                                  : Colors.white38,
                            ),
                          ),
                        ),
                        _CategoryBadge(result: result),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            result.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                        for (final badge in result.badges.take(2)) ...<Widget>[
                          const SizedBox(width: 6),
                          _SmallBadge(text: badge),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: selected ? CloudOSColors.accent : Colors.white24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.result});
  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: result.categoryColor.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: result.categoryColor.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        result.categoryLabel,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.45,
          color: result.categoryColor,
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 8.5,
          color: Colors.white38,
          fontFamily: 'Consolas',
        ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 42),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 30, color: Colors.white24),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white30, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}
