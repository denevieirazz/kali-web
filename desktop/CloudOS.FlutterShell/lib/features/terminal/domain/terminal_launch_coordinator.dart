import 'dart:async';

enum TerminalLaunchProfile { powershell, cmd }

class TerminalLaunchRequest {
  const TerminalLaunchRequest({
    required this.revision,
    required this.profile,
  });

  final int revision;
  final TerminalLaunchProfile profile;
}

class TerminalLaunchCoordinator {
  TerminalLaunchCoordinator._();

  static final StreamController<TerminalLaunchRequest> _controller =
      StreamController<TerminalLaunchRequest>.broadcast(sync: true);
  static TerminalLaunchRequest? _pending;
  static int _revision = 0;

  static Stream<TerminalLaunchRequest> get requests => _controller.stream;

  static TerminalLaunchRequest? takePending() {
    final request = _pending;
    _pending = null;
    return request;
  }

  static void request(TerminalLaunchProfile profile) {
    final request = TerminalLaunchRequest(
      revision: ++_revision,
      profile: profile,
    );
    _pending = request;
    _controller.add(request);
  }

  static void acknowledge(TerminalLaunchRequest request) {
    if (_pending?.revision == request.revision) {
      _pending = null;
    }
  }

  static void resetForTest() {
    _pending = null;
    _revision = 0;
  }
}
