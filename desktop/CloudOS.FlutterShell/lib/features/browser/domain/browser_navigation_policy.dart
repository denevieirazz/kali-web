import 'package:webview_flutter_windows/webview_flutter_windows.dart';

String normalizeBrowserTarget(String input) {
  var value = input.trim();
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    if (value.contains('.') && !value.contains(' ')) {
      value = 'https://$value';
    } else {
      return 'https://www.google.com/search?q=${Uri.encodeComponent(value)}';
    }
  }

  // Empty query parameters ("?&x=y") commonly trigger a canonical redirect.
  // Keeping the canonical URL avoids a superseded-navigation error in WebView2.
  return value.replaceFirst('?&', '?');
}

bool isTransientNavigationError(WebErrorStatus error) {
  return error == WebErrorStatus.connectionAborted ||
      error == WebErrorStatus.operationCanceled;
}
