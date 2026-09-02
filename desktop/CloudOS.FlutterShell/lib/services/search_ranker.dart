import '../models/search_models.dart';
import 'search_query_parser.dart';

class SearchScore {
  const SearchScore({
    required this.score,
    required this.kind,
    required this.matchedTerms,
  });

  const SearchScore.noMatch()
      : score = double.negativeInfinity,
        kind = SearchMatchKind.fallback,
        matchedTerms = const <String>[];

  final double score;
  final SearchMatchKind kind;
  final List<String> matchedTerms;

  bool get matched => score.isFinite && score > double.negativeInfinity;
}

/// Deterministic, dependency-free ranking used by every Search V23 source.
///
/// Ranking deliberately favors exact/prefix matches over fuzzy matching so a
/// short query such as `ter` resolves Terminal before unrelated descriptions.
class SearchRanker {
  SearchRanker({SearchQueryParser parser = const SearchQueryParser()})
      : _parser = parser;

  final SearchQueryParser _parser;

  SearchScore score({
    required SearchQuery query,
    required String title,
    String subtitle = '',
    Iterable<String> keywords = const <String>[],
    double sourceBoost = 0,
    double historyBoost = 0,
  }) {
    if (query.isEmpty) {
      return SearchScore(
        score: 10 + sourceBoost + historyBoost,
        kind: SearchMatchKind.fallback,
        matchedTerms: const <String>[],
      );
    }

    final normalizedTitle = _parser.normalize(title);
    final normalizedSubtitle = _parser.normalize(subtitle);
    final normalizedKeywords = keywords
        .map(_parser.normalize)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final searchable = <String>[
      normalizedTitle,
      normalizedSubtitle,
      ...normalizedKeywords,
    ].join(' ');

    for (final excluded in query.excludedTerms) {
      if (excluded.isNotEmpty && searchable.contains(excluded)) {
        return const SearchScore.noMatch();
      }
    }

    final matched = <String>[];
    var total = sourceBoost + historyBoost;
    var strongest = SearchMatchKind.fallback;
    var strongestWeight = 0.0;

    for (final term in query.terms) {
      final termScore = _scoreTerm(
        term: term,
        title: normalizedTitle,
        subtitle: normalizedSubtitle,
        keywords: normalizedKeywords,
      );
      if (!termScore.matched) return const SearchScore.noMatch();
      matched.add(term);
      total += termScore.score;
      final weight = _kindWeight(termScore.kind);
      if (weight > strongestWeight) {
        strongestWeight = weight;
        strongest = termScore.kind;
      }
    }

    if (query.terms.length > 1) {
      final phrase = query.terms.join(' ');
      if (normalizedTitle == phrase) {
        total += 160;
        strongest = SearchMatchKind.exact;
      } else if (normalizedTitle.startsWith(phrase)) {
        total += 95;
        if (_kindWeight(SearchMatchKind.prefix) > strongestWeight) {
          strongest = SearchMatchKind.prefix;
        }
      } else if (normalizedTitle.contains(phrase)) {
        total += 45;
      }
    }

    // Prefer concise titles when everything else is equal.
    total += 16 / (1 + normalizedTitle.length / 12);

    return SearchScore(
      score: total,
      kind: strongest,
      matchedTerms: List<String>.unmodifiable(matched),
    );
  }

  SearchScore _scoreTerm({
    required String term,
    required String title,
    required String subtitle,
    required List<String> keywords,
  }) {
    if (term.isEmpty) {
      return const SearchScore(
        score: 0,
        kind: SearchMatchKind.fallback,
        matchedTerms: <String>[],
      );
    }

    if (title == term) {
      return SearchScore(
        score: 220,
        kind: SearchMatchKind.exact,
        matchedTerms: <String>[term],
      );
    }
    if (title.startsWith(term)) {
      return SearchScore(
        score: 155,
        kind: SearchMatchKind.prefix,
        matchedTerms: <String>[term],
      );
    }

    final titleWords = _words(title);
    if (titleWords.any((word) => word == term)) {
      return SearchScore(
        score: 135,
        kind: SearchMatchKind.wordPrefix,
        matchedTerms: <String>[term],
      );
    }
    if (titleWords.any((word) => word.startsWith(term))) {
      return SearchScore(
        score: 112,
        kind: SearchMatchKind.wordPrefix,
        matchedTerms: <String>[term],
      );
    }
    if (title.contains(term)) {
      return SearchScore(
        score: 86,
        kind: SearchMatchKind.contains,
        matchedTerms: <String>[term],
      );
    }

    for (final keyword in keywords) {
      if (keyword == term) {
        return SearchScore(
          score: 78,
          kind: SearchMatchKind.keyword,
          matchedTerms: <String>[term],
        );
      }
      if (keyword.startsWith(term)) {
        return SearchScore(
          score: 67,
          kind: SearchMatchKind.keyword,
          matchedTerms: <String>[term],
        );
      }
      if (keyword.contains(term)) {
        return SearchScore(
          score: 54,
          kind: SearchMatchKind.keyword,
          matchedTerms: <String>[term],
        );
      }
    }

    if (subtitle.contains(term)) {
      return SearchScore(
        score: 46,
        kind: SearchMatchKind.contains,
        matchedTerms: <String>[term],
      );
    }

    // Fuzzy matching is intentionally conservative: at least three typed
    // characters and a small edit distance. This avoids irrelevant results
    // while still forgiving common typos such as `termnal`.
    if (term.length >= 3) {
      var best = 99;
      for (final word in titleWords) {
        final distance = _boundedLevenshtein(term, word, 2);
        if (distance < best) best = distance;
      }
      for (final keyword in keywords) {
        for (final word in _words(keyword)) {
          final distance = _boundedLevenshtein(term, word, 2);
          if (distance < best) best = distance;
        }
      }
      if (best <= 1) {
        return SearchScore(
          score: 36 - (best * 8),
          kind: SearchMatchKind.fuzzy,
          matchedTerms: <String>[term],
        );
      }
      if (term.length >= 5 && best == 2) {
        return SearchScore(
          score: 20,
          kind: SearchMatchKind.fuzzy,
          matchedTerms: <String>[term],
        );
      }
    }

    return const SearchScore.noMatch();
  }

  List<String> _words(String value) {
    return value
        .split(RegExp(r'[^a-z0-9_+.-]+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
  }

  double _kindWeight(SearchMatchKind kind) {
    return switch (kind) {
      SearchMatchKind.exact => 7,
      SearchMatchKind.prefix => 6,
      SearchMatchKind.wordPrefix => 5,
      SearchMatchKind.contains => 4,
      SearchMatchKind.keyword => 3,
      SearchMatchKind.fuzzy => 2,
      SearchMatchKind.fallback => 1,
    };
  }

  int _boundedLevenshtein(String a, String b, int maxDistance) {
    if (a == b) return 0;
    if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (index) => index);
    var current = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      var rowMin = current[0];
      for (var j = 1; j <= b.length; j++) {
        final substitution = previous[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
        final insertion = current[j - 1] + 1;
        final deletion = previous[j] + 1;
        var best = substitution;
        if (insertion < best) best = insertion;
        if (deletion < best) best = deletion;
        current[j] = best;
        if (best < rowMin) rowMin = best;
      }
      if (rowMin > maxDistance) return maxDistance + 1;
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }
}
