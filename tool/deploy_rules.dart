import 'dart:io';

const Map<String, String> projectTargets = {
  'admin': 'tranyx-admin-portal',
  'dev': 'tranyx-dev',
  'uat': 'tranyx-uat',
  'prod': 'tranyx-app',
};

void main(List<String> args) async {
  final targetArg = args.isNotEmpty ? args.first.toLowerCase() : 'dev';

  final List<String> targetsToDeploy;
  if (targetArg == 'all') {
    targetsToDeploy = ['admin', 'dev', 'uat', 'prod'];
  } else if (projectTargets.containsKey(targetArg)) {
    targetsToDeploy = [targetArg];
  } else {
    stderr.writeln('Invalid target environment: "$targetArg".');
    stderr.writeln('Available targets: admin, dev, uat, prod, all');
    projectTargets.forEach((k, v) => stderr.writeln('  $k -> $v'));
    exit(1);
  }

  print('=== STEP 1: Synchronizing Firestore Rules from tranyx_workspace ===');
  final syncProcess = await Process.run('dart', ['run', 'tool/sync_rules.dart']);
  stdout.write(syncProcess.stdout);
  if (syncProcess.exitCode != 0) {
    stderr.write(syncProcess.stderr);
    exit(syncProcess.exitCode);
  }

  for (final env in targetsToDeploy) {
    final projectId = projectTargets[env]!;
    print('\n=== STEP 2: Deploying rules to Firebase project "$projectId" ($env) ===');
    final deployProcess = await Process.start(
      'firebase',
      ['deploy', '--only', 'firestore:rules', '--project', projectId],
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await deployProcess.exitCode;
    if (exitCode == 0) {
      print('\n[DEPLOY SUCCESS] Rules successfully released to "$projectId" ($env).');
    } else {
      stderr.writeln('\n[DEPLOY FAILED] Firebase deployment to "$projectId" exited with code $exitCode.');
      exit(exitCode);
    }
  }
}
