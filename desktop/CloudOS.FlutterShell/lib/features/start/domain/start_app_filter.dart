import '../../../models/shell_models.dart';

const startFilters = <String>[
  'Todos',
  'Produtividade',
  'Linux / WSL',
  'Sistema',
  'Utilitários',
];

List<CloudApp> filterStartApps({
  required List<CloudApp> apps,
  required String query,
  required String selectedFilter,
}) {
  final normalized = query.trim().toLowerCase();
  return apps.where((app) {
    final matchesQuery = normalized.isEmpty ||
        app.name.toLowerCase().contains(normalized) ||
        (app.subtitle?.toLowerCase().contains(normalized) ?? false) ||
        (app.distro?.toLowerCase().contains(normalized) ?? false) ||
        app.category.toLowerCase().contains(normalized);

    if (!matchesQuery) return false;
    if (selectedFilter == 'Todos') return true;
    if (selectedFilter == 'Linux / WSL') {
      return app.platform == CloudAppPlatform.linux;
    }
    return app.category == selectedFilter;
  }).toList(growable: false);
}
