import 'dart:io';

import 'package:tranyx_admin_portal/core/services/staff_ops_contract.dart';

/// Reproducible admin Hosting build.
///
/// `.github/workflows/deploy.yml` runs `jaspr build`, and `firebase.json` publishes
/// `build/jaspr` to Firebase project `tranyx-admin-portal`. `pubspec.yaml` sets
/// `jaspr.mode: client` and `jaspr.flutter: plugins`. Locked `jaspr_cli` 0.23.4,
/// matching locked `jaspr` 0.23.4, compiles that mode with Flutter's web UI libraries.
/// Plain `dart run build_runner` uses dart2js without those libraries, so `dart:ui`
/// imports are expected. This script does not copy `build/web` onto `build/jaspr`.
///
/// `--release` writes `build/jaspr` only when the production Enterprise site key is
/// usable and no debug or emulator setting is present. The key is read from the
/// environment and is not printed.
/// `--fixture` compiles with a non-registered key and moves the output to
/// `build/jaspr-fixture`. That directory is not the Hosting public path.
///
///   dart run tool/build_portal.dart --release -- --dart-define=IMGBB_API_KEY=...
///   dart run tool/build_portal.dart --fixture
const String fixtureEnterpriseSiteKey = 'FixtureNotARegisteredEnterpriseKey0001';

Future<void> main(List<String> args) async {
  final fixture = args.contains('--fixture');
  final release = args.contains('--release');
  if (fixture == release) {
    stderr.writeln('Use exactly one of --fixture or --release.');
    exit(64);
  }
  final separator = args.indexOf('--');
  final extra = separator >= 0 ? args.sublist(separator + 1) : const <String>[];

  if (release) {
    final gate = evaluateHostingRelease(
      prodEnterpriseSiteKey: Platform.environment['APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD'] ?? '',
      debugToken: Platform.environment['APP_CHECK_DEBUG_TOKEN'] ?? '',
      functionsBaseUrl: Platform.environment['FUNCTIONS_BASE_URL'] ?? '',
    );
    if (!gate.allowed) {
      stderr.writeln(gate.message);
      exit(1);
    }
    stdout.writeln(gate.message);
    stdout.writeln('Release compile with locked jaspr_cli 0.23.4. Output directory: build/jaspr.');
    final key = Platform.environment['APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD'] ?? '';
    exit(await _jaspr(['--dart-define=APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD=$key', ...extra]));
  }

  stdout.writeln(
    'FIXTURE compile. Not production-ready. The key is not registered with Fraud Defense. Output will be build/jaspr-fixture, not the Hosting directory build/jaspr.',
  );
  final code = await _jaspr([
    '--dart-define=APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD=$fixtureEnterpriseSiteKey',
    ...extra,
  ]);
  if (code != 0) exit(code);
  final src = Directory('build/jaspr');
  if (!src.existsSync()) {
    stderr.writeln('jaspr build exited 0 but build/jaspr was not created.');
    exit(1);
  }
  final dest = Directory('build/jaspr-fixture');
  if (dest.existsSync()) dest.deleteSync(recursive: true);
  src.renameSync(dest.path);
  stdout.writeln('Moved fixture output to build/jaspr-fixture. build/jaspr was not left in place.');
  exit(0);
}

Future<int> _jaspr(List<String> args) async {
  final proc = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'jaspr_cli:jaspr', 'build', ...args],
    mode: ProcessStartMode.inheritStdio,
  );
  return proc.exitCode;
}
