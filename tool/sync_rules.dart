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
