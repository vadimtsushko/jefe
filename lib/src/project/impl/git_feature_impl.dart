// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.commands.git.feature.impl;

import 'dart:async';

import 'package:git/git.dart';
import 'package:jefe/src/git/git.dart';
import 'package:jefe/src/project/git_feature.dart';
import 'package:jefe/src/project/jefe_project.dart';
import 'package:jefe/src/project_commands/project_command.dart'
    show ProjectDependencyGraphCommand, dependencyGraphCommand, executeTask;
import 'package:logging/logging.dart';
import 'package:option/option.dart';
import 'package:pub_semver/pub_semver.dart';

Logger _log = new Logger('jefe.project.commands.git.feature.impl');

class GitFeatureCommandsFlowImpl implements GitFeatureCommands {
  final JefeProject _project;
  GitFeatureCommandsFlowImpl(this._project);

  Future init() => executeTask('git flow init', () async {
        await initGitFlow(await _project.gitDir);
      });

  Future featureStart(String featureName, {bool throwIfExists: false}) =>
      executeTask('git flow feature start', () async {
        final featureNames = await fetchCurrentProjectsFeatureNames();
        if (featureNames.featureExists(featureName)) {
          if (throwIfExists)
            throw new StateError("Feature '$featureName' already exists");
          else if (featureNames.currentFeatureIs(featureName)) {
            // correct feature
            // TODO: could check the branch is correctly based off develop
            _log.info('${_project.name} already on correct feature branch');
          } else {
            return gitCheckout(
                await _project.gitDir, '$featureBranchPrefix$featureName');
          }
        } else {
          return gitFlowFeatureStart(await _project.gitDir, featureName);
        }
      });

  Future featureFinish(String featureName,
          {bool excludeOnlyCommitIf(Commit commit): _dontExclude}) =>
      executeTask('git flow feature finish', () async {
        final GitDir gitDir = await _project.gitDir;
        final Map<String, Commit> commits =
            await gitDir.getCommits('$developBranchName..HEAD');
        _log.info('found ${commits.length} commits on feature branch');
        if (commits.length == 1 && excludeOnlyCommitIf(commits.values.first)) {
          // TODO: we should really delete the feature branch but a bit paranoid
          // doing that for now
          _log.info(
              'feature branch only contains original autogenerated commit.'
              ' Not merging changes');
          await gitCheckout(gitDir, developBranchName);
        } else {
          await gitFlowFeatureFinish(gitDir, featureName);
        }
      });

  Future releaseStart(String releaseName) =>
      executeTask('git flow release start', () async {
        await gitFlowReleaseStart(await _project.gitDir, releaseName);
      });

  Future releaseFinish(String releaseName) =>
      executeTask('git flow release finish', () async {
        var gitDir = await _project.gitDir;
        await gitFlowReleaseFinish(gitDir, releaseName);
        await gitTag(gitDir, releaseName);
        await gitPush(gitDir);
        await gitCheckout(gitDir, developBranchName);
        await gitMerge(gitDir, 'master', ffOnly: false);
        await gitDir.runCommand(['push', 'origin', 'master']);
      });

  @override
  String get developBranchName => 'develop';

  @override
  Future<Option<String>> currentFeatureName() {
    Future<Option<String>> featureNameFor() async {
      final featureNames =
          await new Stream<JefeProject>.fromIterable(_project.depthFirst)
              .asyncMap(
                  (p) async => await gitFlowCurrentFeatureName(await p.gitDir))
              .where((o) => o is Some)
              .map((o) => o.get())
              .toSet();

      if (featureNames.length == 0) {
        return const None();
      } else if (featureNames.length == 1) {
        return new Some<String>(featureNames.first);
      } else {
        throw new StateError('more than one current feature $featureNames');
      }
    }

    return executeTask/*<Option<String>>*/(
        'Get current feature name', featureNameFor);
  }

  @override
  Future<Iterable<Version>> getReleaseVersionTags() {
    Future<Iterable<Version>> fetchTags() async {
      final gitDir = await _project.gitDir;
      return await gitFetchVersionTags(gitDir);
    }
    return executeTask('fetch git release version tags', fetchTags);
  }

  @override
  Future assertNoActiveReleases() =>
      executeTask('check no active releases', () async {
        final releaseNames = await gitFlowReleaseNames(await _project.gitDir);
        if (releaseNames.isNotEmpty) {
          throw new StateError(
              '${_project.name} has an existing release branch. Must finish all active releases first');
        }
      });

  Future<FeatureNames> fetchCurrentProjectsFeatureNames() async {
    final gitDir = await _project.gitDir;
    final results = await Future
        .wait([gitFlowFeatureNames(gitDir), gitFlowCurrentFeatureName(gitDir)]);

    return new FeatureNames(
        (results[0] as Iterable<String>).toSet(), results[1] as Option<String>);
  }
}

bool _dontExclude(Commit c) => false;

class FeatureNames {
  final Set<String> featureNames;
  final Option<String> currentFeatureName;

  FeatureNames(this.featureNames, this.currentFeatureName);

  bool currentFeatureIs(String featureName) =>
      currentFeatureName is Some && currentFeatureName.get() == featureName;

  bool featureExists(String featureName) => featureNames.contains(featureName);
}
