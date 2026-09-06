import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/cloud_system_snapshot.dart';
import '../../../services/cloudos_bridge.dart';
import '../../../services/cloudos_preferences.dart';

class FirstRunDialog extends StatefulWidget {
  const FirstRunDialog({
    super.key,
    required this.preferences,
    required this.bridge,
    required this.snapshot,
    required this.onComplete,
  });

  final CloudOSPreferences preferences;
  final CloudOSBridge bridge;
  final CloudSystemSnapshot snapshot;
  final VoidCallback onComplete;

  static Future<void> showIfNeeded({
    required BuildContext context,
    required CloudOSPreferences preferences,
    required CloudOSBridge bridge,
    required CloudSystemSnapshot snapshot,
    VoidCallback? onComplete,
  }) async {
    if (!preferences.firstRunCompleted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => FirstRunDialog(
          preferences: preferences,
          bridge: bridge,
          snapshot: snapshot,
          onComplete: () {
            Navigator.of(ctx).pop();
            onComplete?.call();
          },
        ),
      );
    }
  }

  @override
  State<FirstRunDialog> createState() => _FirstRunDialogState();
}

class _FirstRunDialogState extends State<FirstRunDialog> {
  int _currentStep = 0;
  static const int _totalSteps = 7;

  // Selections
  late String _selectedTheme;
  late int _selectedAccent;
  late String _performanceProfile;
  late bool _startupEnabled;

  // Hardware telemetry
  CloudHardwareMetrics? _metrics;
  bool _wslDetected = false;
  int _wslDistroCount = 0;
  bool _webView2Detected = true;
  String _hardwareSummary = '';

  @override
  void initState() {
    super.initState();
    _selectedTheme = widget.preferences.appearanceTheme;
    _selectedAccent = widget.preferences.accentColorValue;
    _performanceProfile = widget.preferences.performanceProfile;
    _startupEnabled = widget.preferences.startupEnabled;

    unawaited(_detectSystemCapabilities());
  }

  Future<void> _detectSystemCapabilities() async {
    try {
      final metrics = await widget.bridge.getHardwareMetrics();
      final distros = widget.snapshot.distros;

      if (mounted) {
        setState(() {
          _metrics = metrics;
          _wslDetected = distros.isNotEmpty;
          _wslDistroCount = distros.length;

          final totalRamGb = metrics != null ? (metrics.totalRamMb / 1024.0).round() : 8;
          final cores = Platform.numberOfProcessors;

          // Auto Performance Profile Calculation (Rule 6)
          if (_performanceProfile == 'auto') {
            if (totalRamGb < 8 || cores <= 2) {
              _performanceProfile = 'economy';
            } else if (totalRamGb >= 16 && cores >= 8) {
              _performanceProfile = 'performance';
            } else {
              _performanceProfile = 'balanced';
            }
          }

          _hardwareSummary = '$cores núcleos / $totalRamGb GB RAM / '
              '${_wslDetected ? "$_wslDistroCount distros WSL" : "Windows nativo"}';
        });
      }
    } catch (_) {
      // Fallback to balanced if detection fails
      if (mounted && _performanceProfile == 'auto') {
        setState(() => _performanceProfile = 'balanced');
      }
    }
  }

  Future<void> _finish(bool markCompleted) async {
    widget.preferences.firstRunCompleted = markCompleted;
    widget.preferences.appearanceTheme = _selectedTheme;
    widget.preferences.accentColorValue = _selectedAccent;
    widget.preferences.performanceProfile = _performanceProfile;
    widget.preferences.hardwareSummary = _hardwareSummary;
    widget.preferences.startupEnabled = _startupEnabled;

    await widget.preferences.save();

    unawaited(widget.bridge.setStartupEnabled(_startupEnabled));
    unawaited(widget.bridge.setPerformanceProfile(_performanceProfile));

    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Container(
        width: 680,
        height: 520,
        decoration: BoxDecoration(
          color: const Color(0xFF131B2A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CloudOSColors.border.withValues(alpha: 0.8)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          children: <Widget>[
            // Header Bar
            _buildHeader(),
            const Divider(height: 1, color: CloudOSColors.border),

            // Step Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: _buildStepBody(),
              ),
            ),

            const Divider(height: 1, color: CloudOSColors.border),
            // Footer Navigation
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1522),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Color(_selectedAccent).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.cloud_rounded, color: Color(_selectedAccent), size: 20),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Bem-vindo ao CloudOS',
                style: TextStyle(
                  color: CloudOSColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Configuração rápida e otimização inicial (< 1 minuto)',
                style: TextStyle(color: CloudOSColors.caption, fontSize: 11.5),
              ),
            ],
          ),
          const Spacer(),
          Text(
            'Passo ${_currentStep + 1} de $_totalSteps',
            style: const TextStyle(color: CloudOSColors.caption, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_currentStep) {
      case 0:
        return _buildStepWelcome();
      case 1:
        return _buildStepAppearance();
      case 2:
        return _buildStepHardware();
      case 3:
        return _buildStepWsl();
      case 4:
        return _buildStepBrowser();
      case 5:
        return _buildStepStartup();
      case 6:
        return _buildStepFinish();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStepWelcome() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(_selectedAccent).withValues(alpha: 0.15),
            border: Border.all(color: Color(_selectedAccent).withValues(alpha: 0.4), width: 2),
          ),
          child: Icon(Icons.rocket_launch_rounded, size: 42, color: Color(_selectedAccent)),
        ),
        const SizedBox(height: 20),
        const Text(
          'Experiência Desktop Híbrida de Alta Performance',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          'O CloudOS combina uma interface fluida com a autoridade nativa do Windows, '
          'integração avançada com WSL e um ambiente multitarefa completo em modo usuário.\n\n'
          'Seu Windows Explorer original continua seguro e inalterado (Gate 0).',
          textAlign: TextAlign.center,
          style: TextStyle(color: CloudOSColors.secondary, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildStepAppearance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Escolha sua Aparência',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Selecione o tema do ambiente e a cor de destaque da interface.',
          style: TextStyle(color: CloudOSColors.caption, fontSize: 12.5),
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            _buildThemeOption('dark', 'Escuro', Icons.dark_mode_rounded),
            const SizedBox(width: 14),
            _buildThemeOption('light', 'Claro', Icons.light_mode_rounded),
            const SizedBox(width: 14),
            _buildThemeOption('auto', 'Automático', Icons.brightness_auto_rounded),
          ],
        ),
        const SizedBox(height: 28),
        const Text(
          'Cor de Destaque',
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: <int>[
            0xFF0078D4, // Windows Blue
            0xFF10B981, // Emerald Green
            0xFF8B5CF6, // Purple
            0xFFF59E0B, // Amber
            0xFFEC4899, // Pink
            0xFF06B6D4, // Cyan
          ].map((c) {
            final isSelected = _selectedAccent == c;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: InkWell(
                onTap: () => setState(() => _selectedAccent = c),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 3)
                        : Border.all(color: Colors.transparent),
                    boxShadow: isSelected
                        ? <BoxShadow>[
                            BoxShadow(color: Color(c).withValues(alpha: 0.6), blurRadius: 10),
                          ]
                        : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildThemeOption(String id, String label, IconData icon) {
    final isSelected = _selectedTheme == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTheme = id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isSelected
                ? Color(_selectedAccent).withValues(alpha: 0.15)
                : const Color(0xFF172133),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Color(_selectedAccent) : CloudOSColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 28, color: isSelected ? Color(_selectedAccent) : CloudOSColors.caption),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : CloudOSColors.text,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepHardware() {
    final totalRamGb = _metrics != null ? (_metrics!.totalRamMb / 1024.0).toStringAsFixed(1) : '8.0';
    final cores = Platform.numberOfProcessors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Perfil do Hardware & Desempenho Automático',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'O CloudOS detectou suas especificações locais para calibrar os efeitos visuais.',
          style: TextStyle(color: CloudOSColors.caption, fontSize: 12.5),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1624),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: CloudOSColors.border),
          ),
          child: Row(
            children: <Widget>[
              _buildStatTile('Processador', '$cores núcleos virtuais', Icons.memory_rounded),
              _buildStatTile('Memória RAM', '$totalRamGb GB instalados', Icons.developer_board_rounded),
              _buildStatTile('GPU / Display', 'DirectX / DWM ativo', Icons.desktop_windows_rounded),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Perfil de Desempenho Sugerido',
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            _buildProfileOption('economy', 'Economia', 'Menos blur e animações para hardware leve'),
            const SizedBox(width: 10),
            _buildProfileOption('balanced', 'Equilibrado', 'Fluidez e resposta ideais para o dia a dia'),
            const SizedBox(width: 10),
            _buildProfileOption('performance', 'Desempenho', 'Efeitos completos e máxima fidelidade'),
          ],
        ),
      ],
    );
  }

  Widget _buildStatTile(String label, String value, IconData icon) {
    return Expanded(
      child: Row(
        children: <Widget>[
          Icon(icon, size: 24, color: Color(_selectedAccent)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: const TextStyle(color: CloudOSColors.caption, fontSize: 11)),
                Text(
                  value,
                  style: const TextStyle(color: CloudOSColors.text, fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileOption(String id, String title, String desc) {
    final isSelected = _performanceProfile == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _performanceProfile = id),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? Color(_selectedAccent).withValues(alpha: 0.12) : const Color(0xFF161E2E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Color(_selectedAccent) : CloudOSColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : CloudOSColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: const TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepWsl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Subsistema Windows para Linux (WSL)',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'O CloudOS inclui integração de primeiro nível com distros Linux e WSLg.',
          style: TextStyle(color: CloudOSColors.caption, fontSize: 12.5),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101726),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: CloudOSColors.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                _wslDetected ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 36,
                color: _wslDetected ? const Color(0xFF10B981) : Colors.amberAccent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _wslDetected
                          ? 'WSL Detectado ($_wslDistroCount distribuição instalada)'
                          : 'WSL Não Configurado',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _wslDetected
                          ? 'Terminais nativos e navegação de arquivos Linux estão prontos para uso.'
                          : 'O CloudOS funcionará normalmente apenas com Windows. '
                              'Os recursos Linux podem ser ativados posteriormente a qualquer momento.',
                      style: const TextStyle(color: CloudOSColors.secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepBrowser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Navegador Web Integrado (WebView2)',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Navegação nativa de alta compatibilidade e baixo consumo de recursos.',
          style: TextStyle(color: CloudOSColors.caption, fontSize: 12.5),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101726),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: CloudOSColors.border),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.public_rounded, size: 36, color: Color(0xFF0078D4)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Microsoft Edge WebView2 Runtime Ativo',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _webView2Detected
                          ? 'O Navegador CloudOS está pronto com isolamento de processos e aceleração por hardware.'
                          : 'Runtime WebView2 necessário para o Navegador CloudOS.',
                      style: const TextStyle(color: CloudOSColors.secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepStartup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Inicialização do Sistema',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Defina se o CloudOS deve iniciar automaticamente ao fazer login no Windows.',
          style: TextStyle(color: CloudOSColors.caption, fontSize: 12.5),
        ),
        const SizedBox(height: 24),
        SwitchListTile.adaptive(
          value: _startupEnabled,
          onChanged: (val) => setState(() => _startupEnabled = val),
          tileColor: const Color(0xFF101726),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: CloudOSColors.border),
          ),
          activeTrackColor: Color(_selectedAccent),
          title: const Text(
            'Iniciar CloudOS com o Windows (Recomendado)',
            style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Registrado com segurança per-user em HKCU\\Run. Não altera o shell oficial do Windows (explorer.exe permanece ativo).',
            style: TextStyle(color: CloudOSColors.caption, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _buildStepFinish() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF10B981),
          ),
          child: const Icon(Icons.check_rounded, size: 44, color: Colors.white),
        ),
        const SizedBox(height: 20),
        const Text(
          'Tudo Pronto!',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        const Text(
          'Suas preferências foram aplicadas com sucesso.\n'
          'Explore o menu Iniciar, o gerenciador de Arquivos e os terminais.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: CloudOSColors.secondary, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1522),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: <Widget>[
          if (_currentStep < _totalSteps - 1)
            TextButton(
              onPressed: () => _finish(true),
              child: const Text('Pular', style: TextStyle(color: CloudOSColors.caption)),
            ),
          const Spacer(),
          if (_currentStep > 0 && _currentStep < _totalSteps - 1) ...<Widget>[
            OutlinedButton(
              onPressed: () => setState(() => _currentStep--),
              style: OutlinedButton.styleFrom(
                foregroundColor: CloudOSColors.text,
                side: const BorderSide(color: CloudOSColors.border),
              ),
              child: const Text('Voltar'),
            ),
            const SizedBox(width: 12),
          ],
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Color(_selectedAccent),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
            onPressed: () {
              if (_currentStep < _totalSteps - 1) {
                setState(() => _currentStep++);
              } else {
                _finish(true);
              }
            },
            child: Text(_currentStep == _totalSteps - 1 ? 'Iniciar CloudOS' : 'Avançar'),
          ),
        ],
      ),
    );
  }
}
