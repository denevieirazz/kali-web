import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('xterm preserves VT stream semantics and alternate screen state', () {
    final terminal = Terminal(platform: TerminalTargetPlatform.windows);
    terminal.resize(20, 4);

    terminal.write('progress 10%\rprogress 90%');
    expect(terminal.buffer.getText(), contains('progress 90%'));

    terminal.write('\x1b[2J\x1b[H\x1b[31mRED\x1b[0m');
    expect(terminal.buffer.getText(), startsWith('RED'));

    terminal.write('\x1b[?1049hFULLSCREEN');
    expect(terminal.isUsingAltBuffer, isTrue);
    expect(terminal.buffer.getText(), contains('FULLSCREEN'));
    terminal.write('\x1b[?1049l');
    expect(terminal.isUsingAltBuffer, isFalse);
    expect(terminal.buffer.getText(), startsWith('RED'));
  });

  test('xterm emits interactive keys and reports renderer-driven resize', () {
    final output = <String>[];
    final sizes = <(int, int)>[];
    final terminal = Terminal(
      platform: TerminalTargetPlatform.windows,
      onOutput: output.add,
      onResize: (width, height, _, _) => sizes.add((width, height)),
    );

    terminal.resize(132, 43);
    terminal.keyInput(TerminalKey.arrowUp);
    terminal.keyInput(TerminalKey.home);
    terminal.keyInput(TerminalKey.delete);
    terminal.charInput('c'.codeUnitAt(0), ctrl: true);

    expect(sizes, contains((132, 43)));
    expect(output, contains('\x1b[A'));
    expect(output, contains('\x03'));
  });
}
