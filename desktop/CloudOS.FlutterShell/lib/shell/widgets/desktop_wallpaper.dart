import 'package:flutter/material.dart';

class DesktopWallpaper extends StatelessWidget {
  const DesktopWallpaper({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFF070B10),
                Color(0xFF0D141E),
                Color(0xFF090E16),
              ],
            ),
          ),
        ),
        Positioned(
          right: -100,
          top: -120,
          child: Container(
            width: 500,
            height: 500,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  Color(0x184C9AFF),
                  Color(0x004C9AFF),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 120,
          bottom: -150,
          child: Container(
            width: 540,
            height: 540,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  Color(0x1443C780),
                  Color(0x0043C780),
                ],
              ),
            ),
          ),
        ),
        const Center(
          child: Opacity(
            opacity: 0.035,
            child: Icon(Icons.cloud_rounded, size: 400, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
