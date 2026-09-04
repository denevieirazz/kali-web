import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/cloudos_theme.dart';
import '../../spotlight/domain/spotlight_item.dart';

class CalculatorWindow extends StatefulWidget {
  const CalculatorWindow({super.key});

  @override
  State<CalculatorWindow> createState() => _CalculatorWindowState();
}

class _CalculatorWindowState extends State<CalculatorWindow> {
  String _expression = '';
  String _result = '0';
  final List<String> _history = <String>[];
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onButtonPressed(String label) {
    setState(() {
      if (label == 'C') {
        _expression = '';
        _result = '0';
      } else if (label == '⌫') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
          _evaluatePreview();
        }
      } else if (label == '=') {
        _commitResult();
      } else {
        _expression += label;
        _evaluatePreview();
      }
    });
  }

  void _evaluatePreview() {
    if (_expression.isEmpty) {
      _result = '0';
      return;
    }
    final normalized = _expression.replaceAll('×', '*').replaceAll('÷', '/');
    final eval = SpotlightMathEvaluator.tryEvaluate(normalized);
    if (eval != null) {
      _result = eval % 1 == 0
          ? eval.toInt().toString()
          : eval.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
  }

  void _commitResult() {
    if (_expression.isEmpty) return;
    final normalized = _expression.replaceAll('×', '*').replaceAll('÷', '/');
    final eval = SpotlightMathEvaluator.tryEvaluate(normalized);
    if (eval != null) {
      final formatted = eval % 1 == 0
          ? eval.toInt().toString()
          : eval.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      _history.insert(0, '$_expression = $formatted');
      _expression = formatted;
      _result = formatted;
    } else {
      _result = 'Erro de Sintaxe';
    }
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _onButtonPressed('=');
    } else if (key == LogicalKeyboardKey.backspace) {
      _onButtonPressed('⌫');
    } else if (key == LogicalKeyboardKey.escape) {
      _onButtonPressed('C');
    } else if (event.character != null && '0123456789.+-*/^%()'.contains(event.character!)) {
      var char = event.character!;
      if (char == '*') char = '×';
      if (char == '/') char = '÷';
      _onButtonPressed(char);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <List<String>>[
      <String>['C', '(', ')', '÷'],
      <String>['7', '8', '9', '×'],
      <String>['4', '5', '6', '-'],
      <String>['1', '2', '3', '+'],
      <String>['0', '.', '⌫', '='],
    ];

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Container(
        color: CloudOSColors.background,
        child: Row(
          children: <Widget>[
            // Main Calculator Pad
            Expanded(
              child: Column(
                children: <Widget>[
                  // Display Screen
                  Expanded(
                    flex: 2,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      color: const Color(0xFF0D131F),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            _expression.isEmpty ? ' ' : _expression,
                            style: const TextStyle(
                              color: CloudOSColors.caption,
                              fontSize: 16,
                              fontFamily: 'Consolas',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            alignment: Alignment.centerRight,
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _result,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Consolas',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: CloudOSColors.border),
                  // Keypad Grid
                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: buttons.map((row) {
                          return Expanded(
                            child: Row(
                              children: row.map((label) {
                                final isOperator = '÷×-+='.contains(label);
                                final isSpecial = 'C()⌫'.contains(label);
                                final isAccent = label == '=';

                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Material(
                                      color: isAccent
                                          ? CloudOSColors.accent
                                          : isOperator
                                              ? const Color(0xFF1C273C)
                                              : isSpecial
                                                  ? const Color(0xFF141C2B)
                                                  : const Color(0xFF0F1522),
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () => _onButtonPressed(label),
                                        child: Center(
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              color: isAccent
                                                  ? Colors.white
                                                  : isOperator
                                                      ? CloudOSColors.accent
                                                      : CloudOSColors.text,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // History Sidebar
            Container(
              width: 180,
              decoration: const BoxDecoration(
                color: Color(0xFF0C111C),
                border: Border(left: BorderSide(color: CloudOSColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.history_rounded, size: 16, color: CloudOSColors.accent),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Histórico',
                            style: TextStyle(
                              color: CloudOSColors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_history.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear_all_rounded, size: 16, color: CloudOSColors.caption),
                            tooltip: 'Limpar',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            splashRadius: 14,
                            onPressed: () => setState(_history.clear),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: CloudOSColors.border),
                  Expanded(
                    child: _history.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhum cálculo',
                              style: TextStyle(color: CloudOSColors.caption, fontSize: 11),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _history.length,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  _history[index],
                                  style: const TextStyle(
                                    color: CloudOSColors.caption,
                                    fontSize: 11.5,
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                              );
                            },
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
