import 'package:flutter/material.dart';

enum CloudAppPlatform { windows, linux, cloudos }

class CloudApp {
  const CloudApp({
    required this.id,
    required this.name,
    required this.icon,
    required this.platform,
    this.subtitle,
    this.distro,
    this.category = 'Produtividade',
    this.isPinned = true,
    this.isRecent = false,
    this.canLaunch = true,
    this.displayName,
    this.launchTarget,
    this.source,
    this.availability = 'ready',
    this.capabilities = const <String>[],
  });

  final String id;
  final String name;
  final IconData icon;
  final CloudAppPlatform platform;
  final String? subtitle;
  final String? distro;
  final String category;
  final bool isPinned;
  final bool isRecent;
  final bool canLaunch;
  final String? displayName;
  final String? launchTarget;
  final String? source;
  final String availability;
  final List<String> capabilities;

  CloudApp copyWith({
    String? id,
    String? name,
    IconData? icon,
    CloudAppPlatform? platform,
    String? subtitle,
    String? distro,
    String? category,
    bool? isPinned,
    bool? isRecent,
    bool? canLaunch,
    String? displayName,
    String? launchTarget,
    String? source,
    String? availability,
    List<String>? capabilities,
  }) {
    return CloudApp(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      platform: platform ?? this.platform,
      subtitle: subtitle ?? this.subtitle,
      distro: distro ?? this.distro,
      category: category ?? this.category,
      isPinned: isPinned ?? this.isPinned,
      isRecent: isRecent ?? this.isRecent,
      canLaunch: canLaunch ?? this.canLaunch,
      displayName: displayName ?? this.displayName,
      launchTarget: launchTarget ?? this.launchTarget,
      source: source ?? this.source,
      availability: availability ?? this.availability,
      capabilities: capabilities ?? this.capabilities,
    );
  }
}
