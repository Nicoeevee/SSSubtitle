import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ss_subtitle/app.dart';
import 'package:ss_subtitle/src/core/rust_subtitle_core.dart';
import 'package:ss_subtitle/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(<String>['Noto Sans SC'], license);
  });
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/fonts/OFL-JetBrainsMono.txt',
    );
    yield LicenseEntryWithLineBreaks(<String>['JetBrains Mono'], license);
  });
  await RustLib.init();
  runApp(SSSubtitleApp(core: RustSubtitleCore()));
}
