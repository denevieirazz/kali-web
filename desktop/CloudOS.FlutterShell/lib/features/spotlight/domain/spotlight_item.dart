import 'dart:math' as math;
import 'package:flutter/material.dart';

enum SpotlightItemKind {
  app,
  action,
  calculation,
  shortcut,
}

class SpotlightItem {
  const SpotlightItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.kind,
    required this.onSelect,
    this.badge,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final SpotlightItemKind kind;
  final VoidCallback onSelect;
  final String? badge;
}

class SpotlightMathEvaluator {
  static double? tryEvaluate(String input) {
    final sanitized = input.replaceAll(' ', '');
    if (sanitized.isEmpty) return null;

    final containsOperator = RegExp(r'[\+\-\*\/\^%]').hasMatch(sanitized);
    final isOnlyAllowedChars = RegExp(r'^[\d\.\+\-\*\/\(\)\^%]+$').hasMatch(sanitized);
    if (!containsOperator || !isOnlyAllowedChars) return null;

    try {
      final tokens = _tokenize(sanitized);
      if (tokens.isEmpty) return null;
      var parser = _Parser(tokens);
      final result = parser.parseExpression();
      if (parser.hasNext()) return null;
      if (result.isNaN || result.isInfinite) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  static String formatResult(double value) {
    if (value.remainder(1) == 0) {
      return value.toInt().toString();
    }
    final str = value.toStringAsFixed(6);
    return str.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  static List<String> _tokenize(String s) {
    final tokens = <String>[];
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if ('+-*/()^%'.contains(c)) {
        tokens.add(c);
        i++;
      } else if (RegExp(r'[\d\.]').hasMatch(c)) {
        final start = i;
        while (i < s.length && RegExp(r'[\d\.]').hasMatch(s[i])) {
          i++;
        }
        tokens.add(s.substring(start, i));
      } else {
        i++;
      }
    }
    return tokens;
  }
}

class _Parser {
  _Parser(this.tokens);
  final List<String> tokens;
  int _pos = 0;

  bool hasNext() => _pos < tokens.length;
  String _peek() => _pos < tokens.length ? tokens[_pos] : '';
  String _consume() => tokens[_pos++];

  double parseExpression() {
    var val = parseTerm();
    while (hasNext() && (_peek() == '+' || _peek() == '-')) {
      final op = _consume();
      final right = parseTerm();
      if (op == '+') val += right;
      if (op == '-') val -= right;
    }
    return val;
  }

  double parseTerm() {
    var val = parseFactor();
    while (hasNext() && (_peek() == '*' || _peek() == '/' || _peek() == '^')) {
      final op = _consume();
      final right = parseFactor();
      if (op == '*') val *= right;
      if (op == '/') {
        if (right == 0) throw Exception('Divisão por zero');
        val /= right;
      }
      if (op == '^') {
        val = math.pow(val, right).toDouble();
      }
    }
    return val;
  }

  double parseFactor() {
    if (!hasNext()) throw Exception('Fim inesperado');
    if (_peek() == '-') {
      _consume();
      return -parseFactor();
    }
    if (_peek() == '+') {
      _consume();
      return parseFactor();
    }
    if (_peek() == '(') {
      _consume();
      final val = parseExpression();
      if (hasNext() && _peek() == ')') {
        _consume();
      } else {
        throw Exception('Esperado fecha parênteses');
      }
      return val;
    }
    final token = _consume();
    final parsed = double.tryParse(token);
    if (parsed == null) throw Exception('Número inválido: $token');
    var val = parsed;
    while (hasNext() && _peek() == '%') {
      _consume();
      val = val / 100.0;
    }
    return val;
  }
}
