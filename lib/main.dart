import 'package:flutter/widgets.dart';

import 'bootstrap.dart';
import 'url_strategy_stub.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart'
    as url_strategy;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  url_strategy.configureUrlStrategy();
  await bootstrap();
}
