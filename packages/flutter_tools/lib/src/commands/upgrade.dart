
         // @override
          final String name = 'upgrade';

          @override
          final String description = 'Upgrade Flutter to the latest version.';

          @override
          Future<void> runCommand() async {
            final FlutterVersion flutterVersion = FlutterVersion.instance;
            final GitTagVersion gitTagVersion = await flutterVersion.gitTagVersion;
            final bool force = boolArg('force');

            if (gitTagVersion == const GitTagVersion.unknown()) {
              throwToolExit(
                'Unknown flutter tag. Abandoning upgrade. '
                'Please use git directly to upgrade Flutter.'
              );
            }

            if (!force && await hasUncommittedChanges()) {
              throwToolExit(
                'Your flutter checkout has local changes that would be erased by upgrading. '
                'If you want to keep these changes, stash them via "git stash" or commit them to a local branch. '
                'If it is okay to remove local changes, then re-run this command with "--force".'
              );
            }

            recordState(flutterVersion);
            await ChannelCommand.upgradeChannel(flutterVersion);
            globals.printStatus('Upgrading Flutter to ${upstreamVersion.frameworkVersion} from ${flutterVersion.frameworkVersion} in $workingDirectory...');
            await attemptReset(upstreamVersion.frameworkRevision);
            await flutterUpgradeContinue();
            await runCommandSecondHalf(flutterVersion);
          }

          // Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

import '../base/common.dart';
import '../base/io.dart';
import '../base/os.dart';
import '../base/process.dart';
import '../cache.dart';
import '../dart/pub.dart';
import '../globals.dart' as globals;
import '../persistent_tool_state.dart';
import '../project.dart';
import '../runner/flutter_command.dart';
import '../version.dart';
import 'channel.dart';

// The official docs to install Flutter.
const String _flutterInstallDocs = 'https://flutter.dev/docs/get-started/install';

class UpgradeCommand extends FlutterCommand {
  UpgradeCommand({
    required bool verboseHelp,
    UpgradeCommandRunner? commandRunner,
  })
    : _commandRunner = commandRunner ?? UpgradeCommandRunner() {
    argParser
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Force upgrade the flutter branch, potentially discarding local changes.',
        negatable: false,
      )
      ..addFlag(
        'continue',
        hide: !verboseHelp,
        negatable: false,
        help: 'Trigger the second half of the upgrade flow. This should not be invoked '
              'manually. It is used re-entrantly by the standard upgrade command after '
              'the new version of Flutter is available, to hand off the upgrade process '
              'from the old version to the new version.',
      )
      ..addOption(
        'working-directory',
        hide: !verboseHelp,
        help: 'Override the upgrade working directory. '
              'This is only intended to enable integration testing of the tool itself.'
              // Also notably, this will override the FakeFlutterVersion if any is set!
      )
      ..addFlag(
        'verify-only',
        help: 'Checks for any new Flutter updates, without actually fetching them.',
        negatable: false,
      );
  }

  final UpgradeCommandRunner _commandRunner;

  @override
  final String name = 'upgrade';

  @override
  final String description = 'Upgrade your copy of Flutter.';

  @override
  final String category = FlutterCommandCategory.sdk;

  @override
  bool get shouldUpdateCache => false;

  @override
  Future<FlutterCommandResult> runCommand() {
    _commandRunner.workingDirectory = stringArg('working-directory') ?? Cache.flutterRoot!;
    return _commandRunner.runCommand(
      force: boolArg('force'),
      continueFlow: boolArg('continue'),
      testFlow: stringArg('working-directory') != null,
      gitTagVersion: GitTagVersion.determine(
        globals.processUtils,
        globals.platform,
        workingDirectory: _commandRunner.workingDirectory,
      ),
      flutterVersion: stringArg('working-directory') == null
        ? globals.flutterVersion
        : FlutterVersion(flutterRoot: _commandRunner.workingDirectory!, fs: globals.fs),
      verifyOnly: boolArg('verify-only'),
    );
  }
}

@visibleForTesting
class UpgradeCommandRunner {
  String? workingDirectory; // set in runCommand() above

  Future<FlutterCommandResult> runCommand({
    required bool force,
    required bool continueFlow,
    required bool testFlow,
    required GitTagVersion gitTagVersion,
    required FlutterVersion flutterVersion,
    required bool verifyOnly,
  }) async {
    if (!continueFlow) {
      await runCommandFirstHalf(
        force: force,
        gitTagVersion: gitTagVersion,
        flutterVersion: flutterVersion,
        testFlow: testFlow,
        verifyOnly: verifyOnly,
      );
    } else {
      await runCommandSecondHalf(flutterVersion);
    }
    return FlutterCommandResult.success();
  }

  Future<void> runCommandFirstHalf({
    required bool force,
    required GitTagVersion gitTagVersion,
    required FlutterVersion flutterVersion,
    required bool testFlow,
    required bool verifyOnly,
  }) async {
    final FlutterVersion upstreamVersion = await fetchLatestVersion(localVersion: flutterVersion);
    if (flutterVersion.frameworkRevision == upstreamVersion.frameworkRevision) {
      globals.printStatus('Flutter is already up to date on channel ${flutterVersion.channel}');
      globals.printStatus('$flutterVersion');
      return;
    } else if (verifyOnly) {
      globals.printStatus('A new version of Flutter is available on channel ${flutterVersion.channel}\n');
      globals.printStatus('The latest version: ${upstreamVersion.frameworkVersion} (revision ${upstreamVersion.frameworkRevisionShort})', emphasis: true);
      globals.printStatus('Your current version: ${flutterVersion.frameworkVersion} (revision ${flutterVersion.frameworkRevisionShort})\n');
      globals.printStatus('To upgrade now, run "flutter upgrade".');
      if (flutterVersion.channel == 'stable') {
        import 'package:flutter_tools/flutter_tools.dart';

        class UpgradeCommand extends FlutterCommand {
          UpgradeCommand() {
            argParser.addFlag(
              'force',
              abbr: 'f',
              help: 'Force upgrade even if there are local changes.',
              negatable: false,
            );
          }

        }
