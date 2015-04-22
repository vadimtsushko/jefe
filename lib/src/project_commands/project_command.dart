// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.commands.core;

import 'package:jefe/src/project/project.dart';
import 'dart:async';
import 'package:logging/logging.dart';
import 'package:jefe/src/project/dependency_graph.dart';
import 'dart:io';
import 'package:jefe/src/project_commands/project_command_executor.dart';

Logger _log = new Logger('jefe.project.commands.core');

/// [serial] means the command must execute on a single project at a time and
/// must complete execution on all the projects before the next command may be
/// executed.
///
/// [concurrentProject] means that the command may execute on several projects
/// concurrently but must complete execution on all the projects before the
/// next command may be executed.
///
/// [concurrentCommand]  means that the command may execute on several projects
/// concurrently and the next command may commence on projects where this
/// command has completed before it has completed on all projects
enum CommandConcurrencyMode { serial, concurrentProject, concurrentCommand }

/// A command that operates on a single [Project]
ProjectCommand projectCommand(String name, ProjectFunction function,
        {CommandConcurrencyMode concurrencyMode: CommandConcurrencyMode.concurrentCommand}) =>
    new _DefaultCommand(name, function, concurrencyMode);

/// A command that operates on a single [Project] and the projects it depends on
ProjectCommand projectCommandWithDependencies(
        String name, ProjectWithDependenciesFunction function,
        {CommandConcurrencyMode concurrencyMode: CommandConcurrencyMode.serial}) =>
    new _DefaultCommand(name, function, concurrencyMode);

/// A command that is made up of an ordered list of other commands.
/// For a given [Project] the commands will be executed one at a time in the
/// order provided. Depending on the [concurrencyMode] of the composite command
/// and that of the individual commands, commands may be executing on other
/// [Project]s in the group simultaneously
CompositeProjectCommand projectCommandGroup(
    String name, Iterable<ProjectCommand> commands,
    {CommandConcurrencyMode concurrencyMode: CommandConcurrencyMode.concurrentCommand}) {
  return new _DefaultCompositeProjectCommand(name, commands, concurrencyMode);
}

/// A command that operates on a [DependencyGraph]. Unlike the other commands,
/// a ProjectDependencyGraphCommand is for tasks that require interacting with
/// several projects at once
ProjectDependencyGraphCommand dependencyGraphCommand(
        String name, ProjectDependencyGraphFunction function) =>
    new _DefaultProjectDependencyGraphCommand(name, function);

/// Some function applied to a [Project]
typedef ProjectFunction(Project project);

/// Some function applied to a [Project] with the given dependencies
typedef ProjectWithDependenciesFunction(
    Project project, Iterable<Project> dependencies);

/// A command that can be executed on a [Project] and optionally it's set of
/// [dependencies]
abstract class ProjectCommand {
  String get name;
  CommandConcurrencyMode get concurrencyMode;
  Future process(Project project, {Iterable<Project> dependencies});
}

/// a function that operates on the dependency graph as a whole
typedef Future ProjectDependencyGraphFunction(
    DependencyGraph graph, Directory rootDirectory, ProjectFilter filter);

/// a command that operates on the dependency graph as a whole
abstract class ProjectDependencyGraphCommand {
  String get name;
  Future process(
      DependencyGraph graph, Directory rootDirectory, ProjectFilter filter);
}

/// [concurrencyMode] can be used to limit the concurrencyMode of the
/// individual commands. Each command will execute in the more conservative of
/// the CompositeProjectCommand's value and the ProjectCommand's value.
/// TODO: this is not currently a composite. Either make it one or rename to
/// ProjectCommandGroup or something
abstract class CompositeProjectCommand {
  String get name;
  Iterable<ProjectCommand> get commands;
  CommandConcurrencyMode get concurrencyMode;
}

class _DefaultCommand implements ProjectCommand {
  final String name;
  final Function function;
  final CommandConcurrencyMode concurrencyMode;

  _DefaultCommand(this.name, this.function, this.concurrencyMode);

  @override
  Future process(Project project,
      {Iterable<Project> dependencies: const []}) async {
    final taskDescription = '$name for project ${project.name}';
    _log.info('Executing command "$taskDescription"');
    final stopWatch = new Stopwatch();
    stopWatch.start();

    if (function is! ProjectWithDependenciesFunction &&
        function is! ProjectFunction) {
      throw new ArgumentError('Invalid function passed into process');
    }
    final result = await (function is ProjectWithDependenciesFunction
        ? function(project, dependencies)
        : function(project));
    _log.finer('Completed command "$taskDescription" in ${stopWatch.elapsed}');
    stopWatch.stop();
    return result;
  }
}

class _DefaultCompositeProjectCommand implements CompositeProjectCommand {
  final String name;
  final Iterable<ProjectCommand> commands;
  final CommandConcurrencyMode concurrencyMode;
  _DefaultCompositeProjectCommand(
      this.name, this.commands, this.concurrencyMode);
}

class _DefaultProjectDependencyGraphCommand
    implements ProjectDependencyGraphCommand {
  final String name;
  final ProjectDependencyGraphFunction function;

  _DefaultProjectDependencyGraphCommand(this.name, this.function);

  @override
  Future process(DependencyGraph graph, Directory rootDirectory,
      ProjectFilter filter) async {
    _log.info('Executing command "$name"');
    final stopWatch = new Stopwatch();
    stopWatch.start();

    final result = await function(graph, rootDirectory, filter);

    _log.finer('Completed command "$name" in ${stopWatch.elapsed}');
    stopWatch.stop();
    return result;
  }
}
