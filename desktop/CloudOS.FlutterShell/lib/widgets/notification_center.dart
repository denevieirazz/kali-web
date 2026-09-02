import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/runtime_event_service.dart';
import 'glass_surface.dart';

class NotificationCenter extends StatefulWidget {
  const NotificationCenter({
    this.initialNotifications,
    this.onClose,
    this.runtimeService,
    super.key,
  });

  final List<CloudNotification>? initialNotifications;
  final VoidCallback? onClose;
  final RuntimeEventService? runtimeService;

  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

typedef NotificationCenterPanel = NotificationCenter;

class _NotificationCenterState extends State<NotificationCenter> {
  final List<CloudNotification> _compatItems = <CloudNotification>[];
  late RuntimeEventService _runtime;
  bool _runtimeMode = false;

  @override
  void initState() {
    super.initState();
    _bindSource();
  }

  @override
  void didUpdateWidget(covariant NotificationCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtimeService != widget.runtimeService ||
        oldWidget.initialNotifications != widget.initialNotifications) {
      _unbindRuntime();
      _bindSource();
    }
  }

  void _bindSource() {
    _runtimeMode = widget.initialNotifications == null;
    _compatItems
      ..clear()
      ..addAll(widget.initialNotifications ?? const <CloudNotification>[]);
    _runtime = widget.runtimeService ?? RuntimeEventService.instance;
    if (_runtimeMode) {
      _runtime.start();
      _runtime.addListener(_onRuntimeChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runtime.markAllRead();
      });
    }
  }

  void _unbindRuntime() {
    if (_runtimeMode) _runtime.removeListener(_onRuntimeChanged);
  }

  @override
  void dispose() {
    _unbindRuntime();
    super.dispose();
  }

  void _onRuntimeChanged() {
    if (mounted) setState(() {});
  }

  List<CloudNotification> get _items => _runtimeMode
      ? _runtime.notifications
      : List<CloudNotification>.unmodifiable(_compatItems);

  void _dismiss(String id) {
    if (_runtimeMode) {
      _runtime.dismissNotification(id);
      return;
    }
    setState(() => _compatItems.removeWhere((item) => item.id == id));
  }

  void _clearAll() {
    if (_runtimeMode) {
      _runtime.clearNotifications();
      return;
    }
    setState(_compatItems.clear);
  }

  String _dateString(DateTime now) {
    const weekdays = <String>[
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];
    const months = <String>[
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return '${weekdays[now.weekday - 1]}, ${now.day} de ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final dateString = _dateString(DateTime.now());

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 16, 68),
        child: SizedBox(
          width: 410,
          child: GlassSurface(
            borderRadius: 16,
            blur: 24,
            color: const Color(0xF4121A25),
            borderColor: CloudOSColors.borderStrong,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Centro de Notificações',
                            style: TextStyle(
                              color: CloudOSColors.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateString,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CloudOSColors.caption,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (items.isNotEmpty)
                      TextButton(
                        onPressed: _clearAll,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text(
                          'Limpar Tudo',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: CloudOSColors.accent,
                          ),
                        ),
                      ),
                    if (widget.onClose != null)
                      Tooltip(
                        message: 'Fechar (Esc)',
                        child: IconButton(
                          onPressed: widget.onClose,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ),
                  ],
                ),
                if (_runtimeMode) ...<Widget>[
                  const SizedBox(height: 10),
                  _RuntimeStatusBar(runtime: _runtime),
                ],
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.notifications_off_outlined,
                          size: 36,
                          color: CloudOSColors.caption,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sem novas notificações',
                          style: TextStyle(
                            color: CloudOSColors.secondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _runtimeMode
                              ? 'O EventBus ainda não reportou eventos notificáveis.'
                              : 'Nenhuma notificação foi fornecida.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CloudOSColors.caption,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 430),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _NotificationCard(
                          notification: item,
                          onDismiss: () => _dismiss(item.id),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuntimeStatusBar extends StatelessWidget {
  const _RuntimeStatusBar({required this.runtime});

  final RuntimeEventService runtime;

  Color get _stateColor => switch (runtime.connectionState) {
    RuntimeBrokerConnectionState.connected => Colors.greenAccent,
    RuntimeBrokerConnectionState.connecting => Colors.amberAccent,
    RuntimeBrokerConnectionState.disconnected => Colors.redAccent,
    RuntimeBrokerConnectionState.unavailable => Colors.white38,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: CloudOSColors.elevated.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CloudOSColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _stateColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            'EventBus: ${runtime.connectionStateLabel}',
            style: const TextStyle(
              color: CloudOSColors.secondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (runtime.nativeDroppedEventCount > 0)
            Text(
              '${runtime.nativeDroppedEventCount} evento(s) descartado(s)',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 9.5,
              ),
            )
          else
            Text(
              '${runtime.journal.length} evento(s) na sessão',
              style: const TextStyle(
                color: CloudOSColors.caption,
                fontSize: 9.5,
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onDismiss,
  });

  final CloudNotification notification;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CloudOSColors.elevated.withValues(alpha: 0.45),
        border: Border.all(color: CloudOSColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: CloudOSColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              notification.icon,
              size: 17,
              color: CloudOSColors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        notification.title,
                        style: const TextStyle(
                          color: CloudOSColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      notification.time,
                      style: const TextStyle(
                        color: CloudOSColors.caption,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: onDismiss,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: CloudOSColors.caption,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notification.message,
                  style: const TextStyle(
                    color: CloudOSColors.secondary,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5,
                  children: <Widget>[
                    _Tag(text: notification.source),
                    _Tag(text: notification.category),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: CloudOSColors.border.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: CloudOSColors.caption,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
