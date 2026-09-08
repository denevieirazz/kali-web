import '../models/search_models.dart';

/// Parses the compact, user-facing Search V23 query language.
///
/// Supported prefixes are deliberately declarative. No prefix executes a
/// command; it only narrows a typed catalog/search source.
///
/// Examples:
///   app:terminal
///   file:relatorio ext:pdf
///   settings:som
///   project:cloudos
///   wsl:kali
///   file:"release notes" -old ext:md
class SearchQueryParser {
  const SearchQueryParser();

  static const Map<String, SearchScope> _scopeAliases = <String, SearchScope>{
    'app': SearchScope.apps,
    'apps': SearchScope.apps,
    'aplicativo': SearchScope.apps,
    'aplicativos': SearchScope.apps,
    'file': SearchScope.files,
    'files': SearchScope.files,
    'arquivo': SearchScope.files,
    'arquivos': SearchScope.files,
    'setting': SearchScope.settings,
    'settings': SearchScope.settings,
    'config': SearchScope.settings,
    'configuracao': SearchScope.settings,
    'configuracoes': SearchScope.settings,
    'project': SearchScope.projects,
    'projects': SearchScope.projects,
    'projeto': SearchScope.projects,
    'projetos': SearchScope.projects,
    'wsl': SearchScope.wsl,
    'linux': SearchScope.wsl,
  };

  SearchQuery parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const SearchQuery(
        raw: '',
        normalized: '',
        terms: <String>[],
        scope: SearchScope.all,
        fileExtensions: <String>{},
        excludedTerms: <String>{},
        includeHidden: false,
        explicitScope: false,
      );
    }

    final tokens = _tokenize(trimmed);
    final terms = <String>[];
    final extensions = <String>{};
    final excluded = <String>{};
    var scope = SearchScope.all;
    var explicitScope = false;
    var includeHidden = false;

    for (var i = 0; i < tokens.length; i++) {
      var token = tokens[i].trim();
      if (token.isEmpty) continue;

      final normalizedToken = normalize(token);
      if (normalizedToken == 'hidden:true' ||
          normalizedToken == 'ocultos:true' ||
          normalizedToken == 'hidden') {
        includeHidden = true;
        continue;
      }
      if (normalizedToken == 'hidden:false' ||
          normalizedToken == 'ocultos:false') {
        includeHidden = false;
        continue;
      }

      if (token.startsWith('-') && token.length > 1) {
        final value = normalize(token.substring(1));
        if (value.isNotEmpty) excluded.add(value);
        continue;
      }

      final colon = token.indexOf(':');
      if (colon > 0) {
        final prefix = normalize(token.substring(0, colon));
        var value = token.substring(colon + 1).trim();
        final candidateScope = _scopeAliases[prefix];
        if (candidateScope != null) {
          scope = candidateScope;
          explicitScope = true;
          if (value.isEmpty && i + 1 < tokens.length) {
            value = tokens[++i];
          }
          final normalizedValue = normalize(value);
          if (normalizedValue.isNotEmpty) terms.add(normalizedValue);
          continue;
        }

        if (prefix == 'ext' ||
            prefix == 'extension' ||
            prefix == 'extensao') {
          if (value.isEmpty && i + 1 < tokens.length) {
            value = tokens[++i];
          }
          for (final ext in value.split(',')) {
            final clean = _normalizeExtension(ext);
            if (clean.isNotEmpty) extensions.add(clean);
          }
          if (!explicitScope) scope = SearchScope.files;
          continue;
        }
      }

      final normalized = normalize(token);
      if (normalized.isNotEmpty) terms.add(normalized);
    }

    return SearchQuery(
      raw: raw,
      normalized: normalize(trimmed),
      terms: List<String>.unmodifiable(_dedupePreservingOrder(terms)),
      scope: scope,
      fileExtensions: Set<String>.unmodifiable(extensions),
      excludedTerms: Set<String>.unmodifiable(excluded),
      includeHidden: includeHidden,
      explicitScope: explicitScope,
    );
  }

  List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    var escaping = false;

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) tokens.add(value);
      buffer.clear();
    }

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (escaping) {
        buffer.write(char);
        escaping = false;
        continue;
      }
      if (char == r'\') {
        escaping = true;
        continue;
      }
      if (char == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (!inQuotes && _isWhitespace(char)) {
        flush();
        continue;
      }
      buffer.write(char);
    }
    if (escaping) buffer.write(r'\');
    flush();
    return tokens;
  }

  bool _isWhitespace(String value) {
    return value == ' ' || value == '\t' || value == '\r' || value == '\n';
  }

  String _normalizeExtension(String value) {
    var normalized = normalize(value).trim();
    while (normalized.startsWith('.')) {
      normalized = normalized.substring(1);
    }
    return normalized.replaceAll(RegExp(r'[^a-z0-9_+-]'), '');
  }

  List<String> _dedupePreservingOrder(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      if (value.isEmpty || !seen.add(value)) continue;
      result.add(value);
    }
    return result;
  }

  /// Case-folding and accent folding for Portuguese-friendly ranking.
  ///
  /// This is intentionally deterministic and dependency-free. It covers the
  /// common Latin characters present in Portuguese/English app names without
  /// altering path separators or punctuation used by result IDs.
  String normalize(String input) {
    if (input.isEmpty) return '';
    final lower = input.toLowerCase();
    final out = StringBuffer();
    for (final rune in lower.runes) {
      out.write(_foldRune(rune));
    }
    return out
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _foldRune(int rune) {
    switch (rune) {
      case 0x00E0: // à
      case 0x00E1: // á
      case 0x00E2: // â
      case 0x00E3: // ã
      case 0x00E4: // ä
      case 0x00E5: // å
        return 'a';
      case 0x00E7: // ç
        return 'c';
      case 0x00E8: // è
      case 0x00E9: // é
      case 0x00EA: // ê
      case 0x00EB: // ë
        return 'e';
      case 0x00EC: // ì
      case 0x00ED: // í
      case 0x00EE: // î
      case 0x00EF: // ï
        return 'i';
      case 0x00F1: // ñ
        return 'n';
      case 0x00F2: // ò
      case 0x00F3: // ó
      case 0x00F4: // ô
      case 0x00F5: // õ
      case 0x00F6: // ö
        return 'o';
      case 0x00F9: // ù
      case 0x00FA: // ú
      case 0x00FB: // û
      case 0x00FC: // ü
        return 'u';
      case 0x00FD: // ý
      case 0x00FF: // ÿ
        return 'y';
      case 0x0153: // œ
        return 'oe';
      case 0x00E6: // æ
        return 'ae';
      case 0x00DF: // ß
        return 'ss';
      default:
        return String.fromCharCode(rune);
    }
  }
}
