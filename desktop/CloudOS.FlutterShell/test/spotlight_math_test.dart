import 'package:flutter_test/flutter_test.dart';
import 'package:cloudos_flutter_shell/features/spotlight/domain/spotlight_item.dart';

void main() {
  group('SpotlightMathEvaluator', () {
    test('evaluates basic arithmetic operations', () {
      expect(SpotlightMathEvaluator.tryEvaluate('2 + 2'), 4.0);
      expect(SpotlightMathEvaluator.tryEvaluate('10 - 4'), 6.0);
      expect(SpotlightMathEvaluator.tryEvaluate('3 * 5'), 15.0);
      expect(SpotlightMathEvaluator.tryEvaluate('15 / 3'), 5.0);
    });

    test('respects operator precedence and parentheses', () {
      expect(SpotlightMathEvaluator.tryEvaluate('2 + 3 * 4'), 14.0);
      expect(SpotlightMathEvaluator.tryEvaluate('(2 + 3) * 4'), 20.0);
      expect(SpotlightMathEvaluator.tryEvaluate('100 / (2 + 3) * 2'), 40.0);
    });

    test('supports powers and percentages', () {
      expect(SpotlightMathEvaluator.tryEvaluate('2 ^ 3'), 8.0);
      expect(SpotlightMathEvaluator.tryEvaluate('50%'), 0.5);
      expect(SpotlightMathEvaluator.tryEvaluate('200 * 15%'), 30.0);
    });

    test('handles decimals and whitespace properly', () {
      expect(SpotlightMathEvaluator.tryEvaluate('   3.14   +  2.86 '), 6.0);
      expect(SpotlightMathEvaluator.tryEvaluate('0.5 * 0.5'), 0.25);
    });

    test('formats result cleanly', () {
      expect(SpotlightMathEvaluator.formatResult(4.0), '4');
      expect(SpotlightMathEvaluator.formatResult(3.14159265), '3.141593');
      expect(SpotlightMathEvaluator.formatResult(1000.0), '1000');
    });

    test('returns null on non-math or invalid expressions', () {
      expect(SpotlightMathEvaluator.tryEvaluate(''), isNull);
      expect(SpotlightMathEvaluator.tryEvaluate('hello world'), isNull);
      expect(SpotlightMathEvaluator.tryEvaluate('terminal'), isNull);
      expect(SpotlightMathEvaluator.tryEvaluate('2 +* 3'), isNull);
      expect(SpotlightMathEvaluator.tryEvaluate('(2 + 3'), isNull);
      expect(SpotlightMathEvaluator.tryEvaluate('4 / 0'), isNull);
    });
  });
}
