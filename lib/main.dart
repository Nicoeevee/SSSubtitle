import 'package:flutter/widgets.dart';
import 'package:ss_subtitle/app.dart';
import 'package:ss_subtitle/src/core/rust_subtitle_core.dart';
import 'package:ss_subtitle/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(SSSubtitleApp(core: RustSubtitleCore()));
}
