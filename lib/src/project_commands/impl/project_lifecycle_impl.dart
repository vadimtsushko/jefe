// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.commands.lifecycle.impl;

import 'package:jefe/src/project_commands/git_feature.dart';
import 'package:logging/logging.dart';
import 'package:jefe/src/git/git.dart';
import 'package:jefe/src/project/project.dart';
import 'package:jefe/src/project_commands/project_lifecycle.dart';
import 'package:jefe/src/project_commands/project_command.dart';
import 'package:jefe/src/project_commands/git_commands.dart';
import 'package:jefe/src/project_commands/pub_commands.dart';
import 'package:jefe/src/project_commands/pubspec_commands.dart';
import 'package:jefe/src/project/release_type.dart';
import 'package:git/git.dart';
import 'package:jefe/src/project_commands/project_command_executor.dart';
import 'package:option/option.dart';
import 'package:jefe/src/pub/pub_version.dart';
import 'package:pub_semver/pub_semver.dart';
import 'dart:async';

Logger _log = new Logger('jefe.project.commands.git.feature.impl');

const String featureStartCommitPrefix = 'set up project for new feature';

class ProjectLifecycleImpl implements ProjectLifecycle {
  final GitFeatureCommands _gitFeature;
  final GitCommands _git;
  final PubCommands _pub;
  final PubSpecCommands _pubSpec;

  ProjectLifecycleImpl(
      {GitFeatureCommandsFactory gitFeatureFactory: defaultFlowFeatureFactory})
      : this._gitFeature = gitFeatureFactory(),
        this._git = new GitCommands(),
        this._pub = new PubCommands(),
        this._pubSpec = new PubSpecCommands();

  @override
  CompositeProjectCommand startNewFeature(String featureName,
      {bool doPush: false, bool recursive: true}) {
    return projectCommandGroup(
        'set up project for new feature "$featureName"', [
      _git.assertWorkingTreeClean(),
      _gitFeature.featureStart(featureName),
      _pubSpec.setToPathDependencies(),
      _pub.get(),
      _git.commit('$featureStartCommitPrefix $featureName'),
      _git.push().copy(condition: () => doPush)
    ]);
  }

  // TODO: return to this approach once the concurrency support is implemented
  // to handle it
//  @override
//  CompositeProjectCommand completeFeature(String featureName,
//                                          {bool doPush: false, bool recursive: true}) {
//    return projectCommandGroup('close off feature $featureName', [
//      _gitFeature.featureFinish(featureName),
//      _pubSpec.setToGitDependencies(),
//      _git.commit('set git dependencies for end of feature $featureName'),
//      new OptionalPush(doPush, _git.push()),
//      _pub.get()
//    ]);
//  }

  @override
  ProjectCommand completeFeature(String featureName,
      {bool doPush: false, bool recursive: true}) {
    return projectCommandWithDependencies(
        'complete development of feature $featureName',
        (Project project, Iterable<Project> dependencies) async {
      await _git.assertWorkingTreeClean().process(project);

      final currentBranchName =
          await gitCurrentBranchName(await project.gitDir);
      if (!(currentBranchName == _gitFeature.developBranchName)) {
        await _gitFeature
            .featureFinish(featureName,
                excludeOnlyCommitIf: (Commit c) =>
                    c.message.startsWith(featureStartCommitPrefix))
            .process(project);
      }

      await _pubSpec
          .setToGitDependencies()
          .process(project, dependencies: dependencies);
      await _pub.get().process(project);
      await _git
          .commit('completed development of feature $featureName')
          .process(project);
      await _git.push().process(project);
    });
  }

  @override
  CompositeProjectCommand preRelease(
          {ReleaseType type: ReleaseType.minor,
          bool autoUpdateHostedVersions: false}) =>
      projectCommandGroup('Pre release checks', [
        _git.assertWorkingTreeClean(),
        _gitFeature.assertNoActiveReleases(),
        _git.assertOnBranch(_gitFeature.developBranchName),
        _git.fetch(),
        _git.updateFromRemote('master'),
        _git.updateFromRemote(_gitFeature.developBranchName),
        _git.merge('master'),
        checkReleaseVersions(
            type: type, autoUpdateHostedVersions: autoUpdateHostedVersions),
        _pub.test()
      ]);

  ProjectCommand checkReleaseVersions(
          {ReleaseType type: ReleaseType.minor,
          bool autoUpdateHostedVersions: false}) =>
      projectCommandWithDependencies('check release versions',
          (Project project, Iterable<Project> dependencies) async {
        final ProjectVersions versions = await getCurrentProjectVersion(
            project, dependencies, type, autoUpdateHostedVersions);
        if (versions.newReleaseVersion is Some) {
          _log.info(
              '==> project ${project.name} will be upgraded from version: '
              '${versions.taggedGitVersion} '
              'to: ${versions.newReleaseVersion.get()}. '
              'It will ${versions.isHosted ? "" : "NOT "}be published to pub');
        } else {
          _log.info('project ${project.name} will NOT be upgraded. '
              'It will remain at version: ${versions.pubspecVersion}');
        }
      });

  @override
  ProjectCommand release(
      {ReleaseType type: ReleaseType.minor,
      bool autoUpdateHostedVersions: false}) {
    return projectCommandWithDependencies('Release version: type $type',
        (Project project, Iterable<Project> dependencies) async {
      final ProjectVersions projectVersions = await getCurrentProjectVersion(
          project, dependencies, type, autoUpdateHostedVersions);

      if (!projectVersions.newReleaseRequired) {
        // no release needed
        _log.fine('no changes needing release for ${project.name}');
        return;
      } else {
        final releaseVersion = projectVersions.newReleaseVersion.get();

        _log.fine('new release version $releaseVersion');

        await _gitFeature
            .releaseStart(releaseVersion.toString())
            .process(project);

        if (releaseVersion != projectVersions.pubspecVersion) {
          await project
              .updatePubspec(project.pubspec.copy(version: releaseVersion));
        }

        await _pubSpec
            .setToHostedDependencies()
            .process(project, dependencies: dependencies);

        await _pub.get().process(project);

        await _pub.test().process(project);

        await _git.commit('releasing version $releaseVersion').process(project);

        if (projectVersions.isHosted) {
          await _pub.publish().process(project);
        }

        await _gitFeature
            .releaseFinish(releaseVersion.toString())
            .process(project);

        await _git.push().process(project);
      }
    });
  }

  @override
  ExecutorAwareProjectCommand init({bool doCheckout: true}) {
    return executorAwareCommand('Initialising for development',
        (CommandExecutor executor) async {
      await executor.execute(projectCommandGroup(
          'Initialising for development', [_gitFeature.init(), _git.fetch()]));

      final currentFeatureNameOpt =
          await executor.execute(_gitFeature.currentFeatureName());

      if (currentFeatureNameOpt is Some) {
        var currentFeatureName = currentFeatureNameOpt.get();
        _log.info('Detected existing feature - $currentFeatureName');
        await executor.execute(startNewFeature(currentFeatureName));
      } else {
        await executor.execute(_git
            .checkout(_gitFeature.developBranchName)
            .copy(condition: () => doCheckout));
      }
    });
  }

  Future<Option<Version>> _latestPublishedVersion(Project project) async {
    final Option<HostedPackageVersions> publishedVersionsOpt =
        await _pub.fetchPackageVersions().process(project);

    return publishedVersionsOpt.map(
        (HostedPackageVersions versions) => versions.versions.last.version);
  }

  Future<ProjectVersions> getCurrentProjectVersion(
      Project project,
      Iterable<Project> dependencies,
      ReleaseType type,
      bool autoUpdateHostedVersions) async {
    final GitDir gitDir = await project.gitDir;

    final currentPubspecVersion = project.pubspec.version;

    final taggedVersions =
        await _gitFeature.getReleaseVersionTags().process(project);

    final Option<Version> latestTaggedVersionOpt = taggedVersions.isNotEmpty
        ? new Some(taggedVersions.last)
        : const None();

    final Option<Version> latestPublishedVersionOpt =
        await _latestPublishedVersion(project);

    _log.fine('${project.name}: pubspec version: $currentPubspecVersion; '
        'tagged version: $latestTaggedVersionOpt; '
        'published version: $latestPublishedVersionOpt');

    final Option<Version> releaseVersionOpt = await _getReleaseVersion(
        latestTaggedVersionOpt,
        currentPubspecVersion,
        latestPublishedVersionOpt,
        autoUpdateHostedVersions,
        gitDir,
        type,
        project,
        dependencies);

    return new ProjectVersions(currentPubspecVersion, latestTaggedVersionOpt,
        latestPublishedVersionOpt, releaseVersionOpt);
  }

  Future<Option<Version>> _getReleaseVersion(
      Option<Version> latestTaggedVersionOpt,
      Version currentPubspecVersion,
      Option<Version> latestPublishedVersionOpt,
      bool autoUpdateHostedVersions,
      GitDir gitDir,
      ReleaseType type,
      Project project,
      Iterable<Project> dependencies) async {
    final isHosted = latestPublishedVersionOpt is Some;

    if (latestTaggedVersionOpt is Some) {
      final latestTaggedVersion = latestTaggedVersionOpt.get();
      if (latestTaggedVersion > currentPubspecVersion) {
        throw new StateError('the latest tagged version $latestTaggedVersion'
            ' is greater than the current pubspec version $currentPubspecVersion');
      } else {
        if (latestTaggedVersion < currentPubspecVersion) {
          // manually bumped version
          return new Some(currentPubspecVersion);
        } else {
          // latest released version is same as pubspec version
          final hasChangesSinceLatestTaggedVersion =
              await _hasChangesSince(gitDir, latestTaggedVersion);

          final hasChanges = hasChangesSinceLatestTaggedVersion ||
              (await _pubSpec
                  .haveDependenciesChanged(DependencyType.hosted)
                  .process(project, dependencies: dependencies));

          if (hasChanges) {
            if (isHosted && !autoUpdateHostedVersions) {
              // Hosted packages must observe semantic versioning so not sensible
              // to try to automatically bump version, unless the user explicitly
              // requests it
              throw new ArgumentError(
                  '${project.name} is hosted and has changes. '
                  'The version must be manually changed for hosted packages');
            } else {
              return new Some(type.bump(currentPubspecVersion));
            }
          } else {
            return const None();
          }
        }
      }
    } else {
      // never been tagged
      if (isHosted) {
        if (currentPubspecVersion > latestPublishedVersionOpt.get()) {
          return new Some(currentPubspecVersion);
        } else {
          _log.warning(() =>
              "Project ${project.name} is hosted but has never been tagged in git. "
              "Can't tell if there are unpublished changes. "
              "Will not release as pubspec version is not greater than hosted version");
          return const None();
        }
      } else {
        // never tagged and never published. Assume it needs releasing
        return new Some(currentPubspecVersion);
      }
    }
  }

//  Future<bool> _hasCommitsSince(GitDir gitDir, Version sinceVersion) async {
//    return (await commitCountSince(gitDir, sinceVersion.toString())) > 0;
//  }

  Future<bool> _hasChangesSince(GitDir gitDir, Version sinceVersion) async {
    return (await diffSummarySince(gitDir, sinceVersion.toString())) is Some;
  }
}

class ProjectVersions {
  final Version pubspecVersion;
  final Option<Version> taggedGitVersion;
  final Option<Version> publishedVersion;
  final Option<Version> newReleaseVersion;

  bool get isHosted => publishedVersion is Some;
  bool get newReleaseRequired => newReleaseVersion is Some;

  ProjectVersions(this.pubspecVersion, this.taggedGitVersion,
      this.publishedVersion, this.newReleaseVersion);
}

main() {
  print(new Version(0, 0, 1) > new Version(0, 0, 1, build: '2'));
  print(new Version(0, 0, 1, build: '2') > new Version(0, 0, 1));
}
