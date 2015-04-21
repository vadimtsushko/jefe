// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.commands.git.impl;

import 'package:jefe/src/git/git.dart';
import 'package:logging/logging.dart';
import 'package:jefe/src/project/project.dart';
import 'package:jefe/src/project_commands/project_command.dart';
import 'package:jefe/src/project_commands/git_commands.dart';

Logger _log = new Logger('jefe.project.commands.git.impl');

class GitCommandsImpl implements GitCommands {
  @override
  ProjectCommand commit(String message) => projectCommand('git commit',
      (Project p) async {
    await gitCommit(await p.gitDir, message);
  });

  @override
  ProjectCommand push() => projectCommand('git push', (Project p) async {
    await gitPush(await p.gitDir);
  });

  ProjectCommand fetch() => projectCommand('git fetch', (Project p) async {
    await gitFetch(await p.gitDir);
  });

  @override
  ProjectCommand checkout(String branchName) => projectCommand(
      'git checkout $branchName', (Project p) async {
    await gitCheckout(await p.gitDir, branchName);
  });
}
