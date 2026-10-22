import 'dart:io';

void main() {
  print('=== TRANYX ADMIN PORTAL: Synchronizing Cloud Firestore Rules ===');

  final workspaceDirs = [
    Directory('../tranyx_workspace'),
    Directory('/Users/zeuscajurao/Desktop/tranyx_workspace'),
  ];

  Directory? activeWorkspace;
  for (final dir in workspaceDirs) {
    if (dir.existsSync()) {
      activeWorkspace = dir;
      break;
    }
  }

  if (activeWorkspace == null) {
    stderr.writeln('Warning: tranyx_workspace directory not found. Preserving existing local firestore.rules.');
    exit(0);
  }

  final sourceRules = File('${activeWorkspace.path}/firestore.rules');
  if (!sourceRules.existsSync()) {
    stderr.writeln('Warning: ${sourceRules.path} not found. Attempting to run build_rules.dart in workspace...');
    final buildProc = Process.runSync('dart', ['run', 'tool/build_rules.dart'], workingDirectory: activeWorkspace.path);
    if (buildProc.exitCode != 0) {
      stderr.writeln('Failed to build rules in workspace: ${buildProc.stderr}');
      exit(1);
    }
  }

  if (!sourceRules.existsSync()) {
    stderr.writeln('Error: Could not locate or build firestore.rules from workspace.');
    exit(1);
  }

  // Only sync reviewed rules: the source checkout must be on develop with no local rules changes,
  // or firestore.rules must match TRANYX_RULES_SHA256 (sha256 hex of the exact file to deploy).
  final branch = _git(activeWorkspace.path, ['rev-parse', '--abbrev-ref', 'HEAD']);
  final dirty = _git(activeWorkspace.path, ['status', '--porcelain', '--', 'firestore.rules', 'firestore_rules']);
  if (branch != 'develop' || dirty == null || dirty.isNotEmpty) {
    final expected = (Platform.environment['TRANYX_RULES_SHA256'] ?? '').trim().toLowerCase();
    final actual = _sha256(sourceRules.path);
    if (expected.isEmpty || actual != expected) {
      stderr.writeln('Error: ${activeWorkspace.path} is on "${branch ?? 'unknown'}"'
          '${dirty == null || dirty.isNotEmpty ? ' with uncommitted or unreadable rules changes' : ''}, not a clean develop, '
          'and firestore.rules sha256 ($actual) does not match TRANYX_RULES_SHA256. Sync aborted.');
      exit(1);
    }
  }

  final content = sourceRules.readAsStringSync();

  // Integrity checks
  final openBraces = RegExp(r'\{').allMatches(content).length;
  final closeBraces = RegExp(r'\}').allMatches(content).length;
  if (openBraces != closeBraces) {
    stderr.writeln('Error: Unbalanced braces in source rules ($openBraces open, $closeBraces close). Sync aborted.');
    exit(1);
  }

  final targetFile = File('firestore.rules');
  targetFile.writeAsStringSync(content);

  print('[SYNC SUCCESS] Successfully synchronized firestore.rules from ${sourceRules.path} (${content.length} bytes).');
}

String? _git(String dir, List<String> args) {
  try {
    final result = Process.runSync('git', args, workingDirectory: dir);
    return result.exitCode == 0 ? (result.stdout as String).trim() : null;
  } on ProcessException {
    return null;
  }
}

String? _sha256(String path) {
  for (final cmd in [
    ['shasum', '-a', '256', path],
    ['sha256sum', path],
  ]) {
    try {
      final result = Process.runSync(cmd.first, cmd.sublist(1));
      if (result.exitCode == 0) return (result.stdout as String).split(RegExp(r'\s+')).first.toLowerCase();
    } on ProcessException {
      continue;
    }
  }
  return null;
}
