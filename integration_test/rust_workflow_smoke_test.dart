import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/rust_workflow_smoke_support.dart';

const _offlineSmokeEnabled = bool.fromEnvironment('SSSUBTITLE_OFFLINE_SMOKE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'generated FRB RustSubtitleCore workflow stays responsive offline',
    (_) async => runRustWorkflowSmoke(),
    skip: !_offlineSmokeEnabled,
  );
}
