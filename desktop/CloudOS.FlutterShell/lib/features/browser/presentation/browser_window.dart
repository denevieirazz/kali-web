import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';

class BrowserWindow extends StatefulWidget {
  const BrowserWindow({super.key});

  @override
  State<BrowserWindow> createState() => _BrowserWindowState();
}

class _BrowserWindowState extends State<BrowserWindow> {
  final TextEditingController _urlController =
      TextEditingController(text: 'https://cloudos.internal/portal');
  String _currentUrl = 'https://cloudos.internal/portal';
  bool _isLoading = false;

  void _navigate(String url) {
    setState(() {
      _isLoading = true;
      _currentUrl = url.startsWith('http') ? url : 'https://$url';
      _urlController.text = _currentUrl;
    });
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Expanded(
            child: _buildBrowserContent(),
          ),
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
            onPressed: () {},
          ),
          _NavButton(
            icon: Icons.arrow_forward_rounded,
            tooltip: 'Avançar',
            onPressed: () {},
          ),
          _NavButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Recarregar',
            onPressed: () => _navigate(_urlController.text),
          ),
          _NavButton(
            icon: Icons.home_rounded,
            tooltip: 'Página Inicial',
            onPressed: () => _navigate('https://cloudos.internal/portal'),
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
                  const Icon(Icons.lock_rounded, size: 13, color: CloudOSColors.success),
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
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserContent() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: const Color(0xFF0F141C),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: CloudOSColors.accentSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: CloudOSColors.accent),
                ),
                child: const Icon(
                  Icons.public_rounded,
                  size: 36,
                  color: CloudOSColors.accent,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'CloudOS Web Navigation',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Hospedado via WebView2 runtime • Isolamento de sandbox',
                style: TextStyle(color: CloudOSColors.caption, fontSize: 13),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  _QuickLinkCard(
                    title: 'Google',
                    subtitle: 'Pesquisa Web',
                    icon: Icons.search_rounded,
                    onTap: () => _navigate('https://www.google.com'),
                  ),
                  _QuickLinkCard(
                    title: 'GitHub',
                    subtitle: 'Repositório CloudOS',
                    icon: Icons.code_rounded,
                    onTap: () => _navigate('https://github.com/denevieirazz/kali-web'),
                  ),
                  _QuickLinkCard(
                    title: 'Dev Server',
                    subtitle: 'localhost:3000',
                    icon: Icons.developer_mode_rounded,
                    onTap: () => _navigate('http://localhost:3000'),
                  ),
                  _QuickLinkCard(
                    title: 'Microcamp',
                    subtitle: 'Portal de Tecnologia',
                    icon: Icons.school_rounded,
                    onTap: () => _navigate('https://www.microcampindaiatuba.com.br'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF161B22),
      child: Row(
        children: <Widget>[
          const Icon(Icons.shield_rounded, size: 12, color: CloudOSColors.success),
          const SizedBox(width: 6),
          Text(
            _currentUrl,
            style: const TextStyle(fontSize: 10.5, color: CloudOSColors.caption),
          ),
          const Spacer(),
          const Text(
            'WebView2 Native Host  |  100%',
            style: TextStyle(fontSize: 10.5, color: CloudOSColors.caption),
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
  final VoidCallback onPressed;

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

class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161E2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CloudOSColors.border),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 24, color: CloudOSColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: CloudOSColors.caption,
                      fontSize: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
