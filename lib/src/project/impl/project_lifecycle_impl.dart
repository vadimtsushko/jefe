// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.commands.lifecycle.impl;

import 'dart:async';

import 'package:git/git.dart';
import 'package:jefe/src/git/git.dart';
import 'package:jefe/src/project/git_commands.dart';
import 'package:jefe/src/project/git_feature.dart';
import 'package:jefe/src/project/jefe_project.dart';
import 'package:jefe/src/project/project.dart';
import 'package:jefe/src/project/project_lifecycle.dart';
import 'package:jefe/src/project/pub_commands.dart';
import 'package:jefe/src/project/pubspec_commands.dart';
import 'package:jefe/src/project/release_type.dart';
import 'package:jefe/src/project_commands/project_command.dart'
    show CommandConcurrencyMode, executeTask;
import 'package:logging/logging.dart';
import 'package:option/option.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:jefe/src/project/impl/multi_project_command_support.dart';

Logger _log = new Logger('jefe.project.commands.git.feature.impl');

const String featureStartCommitPrefix = 'set up project for new feature';

class ProjectLifecycleImpl extends Object
    with CommandSupport
    implements ProjectLifecycle {
  final JefeProjectGraph graph;

  ProjectLifecycleImpl(this.graph);

//  GitCommands get _git => graph.git;
//  GitFeatureCommands get _gitFeature => graph.gitFeature;
//  PubCommands get _pub => graph.pub;
//  PubSpecCommands get _pubspec => graph.pubspecCommands;

  @override
  Future startNewFeature(String featureName, {bool doPush: false}) {
    return process('start new feature "$featureName"', (JefeProject p) async {
      await p.git.assertWorkingTreeClean();
      await p.gitFeature.featureStart(featureName);
      await p.pubspecCommands.setToPathDependencies();
      await p.pub.get();
      await p.git.commit('$featureStartCommitPrefix $featureName');
      if (doPush) await p.git.push();
    });
  }

  @override
  Future completeFeature({String featureName, bool doPush: false}) {
    return executeTask('complete development of feature $featureName',
        () async {
      await graph.git.assertWorkingTreeClean();
      final currentFeatureNameOpt = await graph.gitFeature.currentFeatureName();
      if (currentFeatureNameOpt is Some &&
          featureName != null &&
          currentFeatureNameOpt.get() != featureName) {
        throw new StateError('some projects are on a different feature branch '
            '(${currentFeatureNameOpt.get()}) to that specified ($featureName');
      } else if (currentFeatureNameOpt is None && featureName == null) {
        // nothing to do. We are not on any feature branch and no feature name
        // requested
        return null;
      } else {
        final finishingFeatureName = featureName ?? currentFeatureNameOpt.get();

        Future completeOnProject(JefeProject p) async {
          if (await p.gitFeature.isOnDevelopBranch) {
            _log.finer(
                'project ${p.name} is already on develop branch. Nothing to do');
            return;
          }
          if ((await p.gitFeature.currentFeatureName()).getOrElse(() => null) !=
              finishingFeatureName) {
            throw new StateError(
                "project ${p.name} is neither on feature branch or develop");
          }

          await p.gitFeature.featureFinish(featureName,
              excludeOnlyCommitIf: (Commit c) =>
                  c.message.startsWith(featureStartCommitPrefix));

          await p.pubspecCommands.setToGitDependencies();
          await p.pub.get();
          await p.git.commit('completed development of feature $featureName');

          if (doPush) await p.git.push();
        }

        return process(
            'complete feature $finishingFeatureName', completeOnProject,
            mode: CommandConcurrencyMode.serialDepthFirst);
      }
    });
  }

  @override
  Future preRelease(
      {ReleaseType type: ReleaseType.minor,
      bool autoUpdateHostedVersions: false,
      bool recursive: true}) {
    if (!recursive)
      return preReleaseCurrentProject(type, autoUpdateHostedVersions);

    Future doPreRelease(JefeProject project) => project.lifecycle.preRelease(
        type: type,
        autoUpdateHostedVersions: autoUpdateHostedVersions,
        recursive: false);

    return executeTask('Pre release checks: type $type',
        () => graph.processDepthFirst(doPreRelease));
  }

  Future preReleaseCurrentProject(
          ReleaseType type, bool autoUpdateHostedVersions) =>
      executeTask('Pre release checks for project ${graph.name}', () async {
        await _git.assertWorkingTreeClean();
        await _gitFeature.assertNoActiveReleases();
        await _git.assertOnBranch(_gitFeature.developBranchName);
        await _git.fetch();
        await _git.updateFromRemote('master');
        await _git.updateFromRemote(_gitFeature.developBranchName);
        await _git.merge('master');
        await checkReleaseVersions(
            type: type, autoUpdateHostedVersions: autoUpdateHostedVersions);
        await _pub.test();
      });

  Future checkReleaseVersions(
          {ReleaseType type: ReleaseType.minor,
          bool autoUpdateHostedVersions: false}) =>
      executeTask('check release versions', () async {
        final ProjectVersions versions = await getCurrentProjectVersions(
            graph, type, autoUpdateHostedVersions);
        if (versions.newReleaseVersion is Some) {
          _log.info('==> project ${graph.name} will be upgraded from version: '
              '${versions.taggedGitVersion} '
              'to: ${versions.newReleaseVersion.get()}. '
              'It will ${versions.hasBeenPublished ? "" : "NOT "}be published to pub');
        } else {
          _log.info('project ${graph.name} will NOT be upgraded. '
              'It will remain at version: ${versions.pubspecVersion}');
        }
      });

  @override
  Future release(
      {ReleaseType type: ReleaseType.minor,
      bool autoUpdateHostedVersions: false,
      bool recursive: true}) {
    if (!recursive)
      return releaseCurrentProject(type, autoUpdateHostedVersions);

    Future doRelease(JefeProject project) => project.lifecycle.release(
        type: type,
        autoUpdateHostedVersions: autoUpdateHostedVersions,
        recursive: false);

    return executeTask('Release version: type $type',
        () => graph.processDepthFirst(doRelease));
  }

  Future releaseCurrentProject(
      ReleaseType type, bool autoUpdateHostedVersions) {
    return executeTask('Release version: type $type for project ${graph.name}',
        () async {
      final ProjectVersions projectVersions = await getCurrentProjectVersions(
          graph, type, autoUpdateHostedVersions);

      if (!projectVersions.newReleaseRequired) {
        // no release needed
        _log.fine('no changes needing release for ${graph.name}');
        return;
      } else {
        final releaseVersion = projectVersions.newReleaseVersion.get();

        _log.fine('new release version $releaseVersion');

        await _gitFeature.releaseStart(releaseVersion.toString());

        if (releaseVersion != projectVersions.pubspecVersion) {
          await graph
              .updatePubspec(graph.pubspec.copy(version: releaseVersion));
        }

        await _pubspec.setToHostedDependencies();

        await _pub.get();

        await _pub.test();

        await _git.commit('releasing version $releaseVersion');

        if (projectVersions.currentVersions.isHosted) {
          await _pub.publish();
        }

        await _gitFeature.releaseFinish(releaseVersion.toString());

        await _git.push();
      }
    });
  }

  @override
  Future init({bool doCheckout: true}) {
    if (!recursive) return initCurrentProject(doCheckout);

    Future doInit(JefeProject project) =>
        project.lifecycle.init(doCheckout: doCheckout, recursive: false);

    return executeTask(
        'Initialising for development', () => graph.processDepthFirst(doInit));
  }

  Future initCurrentProject(bool doCheckout) {
    return executeTask('Initialising for development for project ${graph.name}',
        () async {
      await _git.fetch();
      await _gitFeature.init();

      final currentFeatureNameOpt = await _gitFeature.currentFeatureName();

      if (currentFeatureNameOpt is Some) {
        final currentFeatureName = currentFeatureNameOpt.get();
        _log.info('Detected existing feature - $currentFeatureName');
        await startNewFeature(currentFeatureName);
      } else {
        if (doCheckout) await _git.checkout(_gitFeature.developBranchName);
      }
    });
  }

  Future<ProjectVersions> getCurrentProjectVersions(JefeProject project,
      ReleaseType type, bool autoUpdateHostedVersions) async {
    final currentProjectVersions = await project.projectVersions;

    _log.fine('${project.name}: $currentProjectVersions');

    final Option<Version> releaseVersionOpt = await _getReleaseVersion(
        currentProjectVersions, autoUpdateHostedVersions, type, project);

    return new ProjectVersions(currentProjectVersions, releaseVersionOpt);
  }

  Future<Option<Version>> _getReleaseVersion(
      ProjectVersions2 currentVersions,
      bool autoUpdateHostedVersions,
      ReleaseType type,
      JefeProject project) async {
    final hasBeenPublished = currentVersions.hasBeenPublished;
    final isHosted = currentVersions.isHosted;
    final currentPubspecVersion = currentVersions.pubspecVersion;

    if (currentVersions.hasBeenGitTagged) {
      final latestTaggedVersion = currentVersions.taggedGitVersion.get();
      if (latestTaggedVersion > currentPubspecVersion) {
        throw new StateError('the latest tagged version $latestTaggedVersion'
            ' is greater than the current pubspec version $currentPubspecVersion');
      } else if (latestTaggedVersion < currentPubspecVersion) {
        // manually bumped version
        return new Some<Version>(currentPubspecVersion);
      } else {
        // latest released version is same as pubspec version
        if (await hasChanges) {
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
    } else {
      // never been tagged
      if (hasBeenPublished) {
        if (currentPubspecVersion > currentVersions.publishedVersion.get()) {
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

  Future<bool> get hasChanges async =>
      new Stream<bool>.fromFutures(<Future<bool>>[
        _gitFeature.hasChangesSinceLatestTaggedVersion,
        _pubspec.haveDependenciesChanged(DependencyType.hosted)
      ]).any((b) => b);
}

class ProjectLifecycleSingleProjectImpl implements ProjectLifecycle {
  final JefeProject _project;
  ProjectLifecycleSingleProjectImpl(this._project);

  GitCommands get _git => _project.singleProjectCommands.git;
  GitFeatureCommands get _gitFeature =>
      _project.gitFeature.singleProjectCommandFor(_project);
  PubCommands get _pub => _project.pub.singleProjectCommandFor(_project);
  PubSpecCommands get _pubspec =>
      _project.pubspecCommands.singleProjectCommandFor(_project);

  @override
  Future startNewFeature(String featureName, {bool doPush: false}) {
    return executeTask(
        'set up project for new feature "$featureName" for project ${_project.name}',
        () async {
      await _git.assertWorkingTreeClean();
      await _gitFeature.featureStart(featureName);
      await _pubspec.setToPathDependencies();
      await _pub.get();
      await _git.commit('$featureStartCommitPrefix $featureName');
      if (doPush) await _git.push();
    });
  }

  @override
  Future completeFeature(String featureName, {bool doPush: false}) async {
    await _git.assertWorkingTreeClean();

    final currentBranchName = await gitCurrentBranchName(await _project.gitDir);
    if (!(currentBranchName == _gitFeature.developBranchName)) {
      await _gitFeature.featureFinish(featureName,
          excludeOnlyCommitIf: (Commit c) =>
              c.message.startsWith(featureStartCommitPrefix));
    }

    /// TODO: this step must be done depthFirst
    /// One solution is just to do the whole completeFeature depthFirst
    await _pubspec.setToGitDependencies();
    await _pub.get();
    await _git.commit('completed development of feature $featureName');

    if (doPush) await _git.push();
  }

  @override
  Future preRelease(
      {ReleaseType type: ReleaseType.minor,
      bool autoUpdateHostedVersions: false,
      bool recursive: true}) {
    if (!recursive)
      return preReleaseCurrentProject(type, autoUpdateHostedVersions);

    Future doPreRelease(JefeProject project) => project.lifecycle.preRelease(
        type: type,
        autoUpdateHostedVersions: autoUpdateHostedVersions,
        recursive: false);

    return executeTask('Pre release checks: type $type',
        () => _project.processDepthFirst(doPreRelease));
  }

  Future preReleaseCurrentProject(
          ReleaseType type, bool autoUpdateHostedVersions) =>
      executeTask('Pre release checks for project ${_project.name}', () async {
        await _git.assertWorkingTreeClean();
        await _gitFeature.assertNoActiveReleases();
        await _git.assertOnBranch(_gitFeature.developBranchName);
        await _git.fetch();
        await _git.updateFromRemote('master');
        await _git.updateFromRemote(_gitFeature.developBranchName);
        await _git.merge('master');
        await checkReleaseVersions(
            type: type, autoUpdateHostedVersions: autoUpdateHostedVersions);
        await _pub.test();
      });

  Future checkReleaseVersions(
          {ReleaseType type: ReleaseType.minor,
          bool autoUpdateHostedVersions: false}) =>
      executeTask('check release versions', () async {
        final ProjectVersions versions = await getCurrentProjectVersions(
            _project, type, autoUpdateHostedVersions);
        if (versions.newReleaseVersion is Some) {
          _log.info(
              '==> project ${_project.name} will be upgraded from version: '
              '${versions.taggedGitVersion} '
              'to: ${versions.newReleaseVersion.get()}. '
              'It will ${versions.hasBeenPublished ? "" : "NOT "}be published to pub');
        } else {
          _log.info('project ${_project.name} will NOT be upgraded. '
              'It will remain at version: ${versions.pubspecVersion}');
        }
      });

  @override
  Future release(
      {ReleaseType type: ReleaseType.minor,
      bool autoUpdateHostedVersions: false,
      bool recursive: true}) {
    if (!recursive)
      return releaseCurrentProject(type, autoUpdateHostedVersions);

    Future doRelease(JefeProject project) => project.lifecycle.release(
        type: type,
        autoUpdateHostedVersions: autoUpdateHostedVersions,
        recursive: false);

    return executeTask('Release version: type $type',
        () => _project.processDepthFirst(doRelease));
  }

  Future releaseCurrentProject(
      ReleaseType type, bool autoUpdateHostedVersions) {
    return executeTask(
        'Release version: type $type for project ${_project.name}', () async {
      final ProjectVersions projectVersions = await getCurrentProjectVersions(
          _project, type, autoUpdateHostedVersions);

      if (!projectVersions.newReleaseRequired) {
        // no release needed
        _log.fine('no changes needing release for ${_project.name}');
        return;
      } else {
        final releaseVersion = projectVersions.newReleaseVersion.get();

        _log.fine('new release version $releaseVersion');

        await _gitFeature.releaseStart(releaseVersion.toString());

        if (releaseVersion != projectVersions.pubspecVersion) {
          await _project
              .updatePubspec(_project.pubspec.copy(version: releaseVersion));
        }

        await _pubspec.setToHostedDependencies();

        await _pub.get();

        await _pub.test();

        await _git.commit('releasing version $releaseVersion');

        if (projectVersions.currentVersions.isHosted) {
          await _pub.publish();
        }

        await _gitFeature.releaseFinish(releaseVersion.toString());

        await _git.push();
      }
    });
  }

  @override
  Future init({bool doCheckout: true}) {
    if (!recursive) return initCurrentProject(doCheckout);

    Future doInit(JefeProject project) =>
        project.lifecycle.init(doCheckout: doCheckout, recursive: false);

    return executeTask('Initialising for development',
        () => _project.processDepthFirst(doInit));
  }

  Future initCurrentProject(bool doCheckout) {
    return executeTask(
        'Initialising for development for project ${_project.name}', () async {
      await _git.fetch();
      await _gitFeature.init();

      final currentFeatureNameOpt = await _gitFeature.currentFeatureName();

      if (currentFeatureNameOpt is Some) {
        final currentFeatureName = currentFeatureNameOpt.get();
        _log.info('Detected existing feature - $currentFeatureName');
        await startNewFeature(currentFeatureName);
      } else {
        if (doCheckout) await _git.checkout(_gitFeature.developBranchName);
      }
    });
  }

  Future<ProjectVersions> getCurrentProjectVersions(JefeProject project,
      ReleaseType type, bool autoUpdateHostedVersions) async {
    final currentProjectVersions = await project.projectVersions;

    _log.fine('${project.name}: $currentProjectVersions');

    final Option<Version> releaseVersionOpt = await _getReleaseVersion(
        currentProjectVersions, autoUpdateHostedVersions, type, project);

    return new ProjectVersions(currentProjectVersions, releaseVersionOpt);
  }

  Future<Option<Version>> _getReleaseVersion(
      ProjectVersions2 currentVersions,
      bool autoUpdateHostedVersions,
      ReleaseType type,
      JefeProject project) async {
    final hasBeenPublished = currentVersions.hasBeenPublished;
    final isHosted = currentVersions.isHosted;
    final currentPubspecVersion = currentVersions.pubspecVersion;

    if (currentVersions.hasBeenGitTagged) {
      final latestTaggedVersion = currentVersions.taggedGitVersion.get();
      if (latestTaggedVersion > currentPubspecVersion) {
        throw new StateError('the latest tagged version $latestTaggedVersion'
            ' is greater than the current pubspec version $currentPubspecVersion');
      } else if (latestTaggedVersion < currentPubspecVersion) {
        // manually bumped version
        return new Some<Version>(currentPubspecVersion);
      } else {
        // latest released version is same as pubspec version
        if (await hasChanges) {
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
    } else {
      // never been tagged
      if (hasBeenPublished) {
        if (currentPubspecVersion > currentVersions.publishedVersion.get()) {
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

  Future<bool> get hasChanges async =>
      new Stream<bool>.fromFutures(<Future<bool>>[
        _gitFeature.hasChangesSinceLatestTaggedVersion,
        _pubspec.haveDependenciesChanged(DependencyType.hosted)
      ]).any((b) => b);
}

class ProjectVersions {
  final ProjectVersions2 currentVersions;
  final Option<Version> newReleaseVersion;

  Version get pubspecVersion => currentVersions.pubspecVersion;
  Option<Version> get taggedGitVersion => currentVersions.taggedGitVersion;
  Option<Version> get publishedVersion => currentVersions.publishedVersion;

  bool get hasBeenPublished => publishedVersion is Some;
  bool get newReleaseRequired => newReleaseVersion is Some;

  ProjectVersions(this.currentVersions, this.newReleaseVersion);
}
