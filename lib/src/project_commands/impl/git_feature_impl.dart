// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.commands.git.feature.impl;

import 'package:jefe/src/project_commands/git_feature.dart';
import 'package:jefe/src/git/git.dart';
import 'package:logging/logging.dart';
import 'package:jefe/src/project/project.dart';
import 'package:jefe/src/project_commands/project_command.dart';
import 'package:jefe/src/project/dependency_graph.dart';
import 'dart:io';
import 'package:option/option.dart';
import 'dart:async';

Logger _log = new Logger('jefe.project.commands.git.feature.impl');

class GitFeatureCommandsFlowImpl implements GitFeatureCommands {
  ProjectCommand init() => projectCommand('git flow init', (Project p) async {
    await initGitFlow(await p.gitDir);
  });

  ProjectCommand featureStart(String featureName) => projectCommand(
      'git flow feature start', (Project p) async {
    await gitFlowFeatureStart(await p.gitDir, featureName);
  });

  ProjectCommand featureFinish(String featureName) => projectCommand(
      'git flow feature finish', (Project p) async {
    await gitFlowFeatureFinish(await p.gitDir, featureName);
  });

  ProjectCommand releaseStart(String releaseName) => projectCommand(
      'git flow release start', (Project p) async {
    await gitFlowReleaseStart(await p.gitDir, releaseName);
  });

  ProjectCommand releaseFinish(String releaseName) => projectCommand(
      'git flow release finish', (Project p) async {
    var gitDir = await p.gitDir;
    await gitFlowReleaseFinish(gitDir, releaseName);
    await gitTag(gitDir, releaseName);
  });

  @override
  String get developBranchName => 'develop';

  ProjectDependencyGraphCommand currentFeatureName() => dependencyGraphCommand(
      'Get current feature name',
      (DependencyGraph graph, Directory rootDirectory) async {
    final featureNames = await new Stream.fromIterable(graph.depthFirst)
        .asyncMap((pd) async =>
            await gitFlowCurrentFeatureName(await pd.project.gitDir))
        .where((o) => o is Some)
        .map((o) => o.get())
        .toSet();

    if (featureNames.length == 0) {
      return const None();
    } else if (featureNames.length == 1) {
      return new Some(featureNames.first);
    } else {
      throw new StateError('more than one current feature $featureNames');
    }
  });
}
