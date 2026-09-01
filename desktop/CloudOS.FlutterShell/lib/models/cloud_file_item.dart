import 'package:flutter/material.dart';

enum CloudFileSource { cloudDrive, windows, linux, trash }

class CloudFileItem {
  const CloudFileItem({
    required this.name,
    required this.path,
    required this.isFolder,
    required this.sizeFormatted,
    required this.modifiedFormatted,
    required this.source,
    this.entryId,
    this.icon,
    this.extension,
  });

  final String name;
  final String path;
  final bool isFolder;
  final String sizeFormatted;
  final String modifiedFormatted;
  final CloudFileSource source;
  final String? entryId;
  final IconData? icon;
  final String? extension;
}
