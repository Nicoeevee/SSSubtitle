import 'package:flutter_test/flutter_test.dart';

import 'rust_workflow_smoke_support.dart';

const _offlineSmokeEnabled = bool.fromEnvironment('SSSUBTITLE_OFFLINE_SMOKE');

void main() {
  test(
    'generated FRB RustSubtitleCore Web workflow stays responsive offline',
    runRustWorkflowSmoke,
    skip: !_offlineSmokeEnabled,
  );
}
