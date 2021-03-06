// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.commands.process.impl;

import 'dart:async';

import 'package:jefe/src/project/impl/multi_project_command_support.dart';
import 'package:jefe/src/project/jefe_project.dart';
import 'package:jefe/src/project/process_commands.dart';
import 'package:jefe/src/project_commands/project_command.dart';
import 'package:jefe/src/util/process_utils.dart';
import 'package:logging/logging.dart';
import 'package:quiver/iterables.dart';

Logger _log = new Logger('jefe.project.commands.process.impl');

ProcessCommands createProcessCommands(JefeProjectGraph graph,
    {bool multiProject: true,
    CommandConcurrencyMode defaultConcurrencyMode,
    ProjectFilter projectFilter}) {
  return multiProject
      ? new ProcessCommandsMultiProjectImpl(graph,
          defaultConcurrencyMode: defaultConcurrencyMode,
          projectFilter: projectFilter)
      : new ProcessCommandsSingleProjectImpl(graph as JefeProject);
}

class ProcessCommandsSingleProjectImpl
    extends SingleProjectCommandSupport<ProcessCommands>
    implements ProcessCommands {
  ProcessCommandsSingleProjectImpl(JefeProject project)
      : super(
            (JefeProject p) async =>
                new _ProcessCommandsSingleProjectImpl(project),
            project);
}

class ProcessCommandsMultiProjectImpl
    extends MultiProjectCommandSupport<ProcessCommands>
    implements ProcessCommands {
  ProcessCommandsMultiProjectImpl(JefeProjectGraph graph,
      {CommandConcurrencyMode defaultConcurrencyMode,
      ProjectFilter projectFilter})
      : super(graph,
            (JefeProject p) async => new ProcessCommandsSingleProjectImpl(p),
            defaultConcurrencyMode: defaultConcurrencyMode,
            projectFilter: projectFilter);

  @override
  Future<Iterable<ProcessCommandResult>> execute(
      String command, List<String> args) async {
    Iterable<ProcessCommandResult> concatResults(
        Iterable<ProcessCommandResult> previous,
        Iterable<ProcessCommandResult> current) {
      return concat(<Iterable<ProcessCommandResult>>[previous, current])
          as Iterable<ProcessCommandResult>;
    }
    return process/*<Iterable<ProcessCommandResult>>*/(
        'process',
        (JefeProject p) async =>
            (await singleProjectCommandFactory(p)).execute(command, args),
        combine: concatResults,
        filter: projectFilter);
  }
}

class _ProcessCommandsSingleProjectImpl implements ProcessCommands {
  final JefeProject _project;

  _ProcessCommandsSingleProjectImpl(this._project);

  @override
  Future<Iterable<ProcessCommandResult>> execute(
          String command, List<String> args) async =>
      <ProcessCommandResult>[
        new ProcessCommandResult(
            await runCommand(command, args,
                processWorkingDir: _project.installDirectory.path),
            _project)
      ];
}
