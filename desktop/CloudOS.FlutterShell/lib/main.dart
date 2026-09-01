import 'package:flutter/widgets.dart';

import 'app/cloudos_app.dart';

export 'app/cloudos_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CloudOSApp());
}
