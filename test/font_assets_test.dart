import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'JetBrains Mono Medium is bundled for offline preview rendering',
    () async {
      GoogleFonts.config.allowRuntimeFetching = false;

      final style = GoogleFonts.jetBrainsMono(
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
      );

      expect(style.fontFamily, 'JetBrainsMono_500');
      expect(style.fontFamilyFallback, contains('JetBrainsMono'));

      final fontData = await rootBundle.load(
        'assets/fonts/JetBrainsMono-Medium.ttf',
      );
      expect(fontData.lengthInBytes, 112180);

      await GoogleFonts.pendingFonts();
    },
  );
}
