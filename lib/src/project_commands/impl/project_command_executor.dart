// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.commands.executor.impl;

import 'package:jefe/src/project/project.dart';

import 'package:logging/logging.dart';
import 'dart:async';
import 'package:jefe/src/project_commands/project_command.dart';
import 'package:jefe/src/project_commands/project_command_executor.dart';
import 'dart:collection';
import 'package:option/option.dart';
import 'package:frappe/frappe.dart';
import 'package:jefe/src/util/frappe_utils.dart';
import 'package:jefe/src/project/dependency_graph.dart';
import 'package:jefe/src/project/project_group.dart';

Logger _log = new Logger('jefe.project.commands.impl');

class CommandExecutorImpl implements CommandExecutor {
  final ProjectGroup _projectGroup;

  CommandExecutorImpl(this._projectGroup);

  Future execute(ProjectCommand command) async {
    return await _processDependenciesDepthFirst(
        (Project project, Iterable<Project> dependencies) =>
            command.process(project, dependencies: dependencies));
  }

  Future _processDependenciesDepthFirst(
      process(Project project, Iterable<Project> dependencies)) async {
    return (await _projectGroup.dependencyGraph).processDepthFirst(process);
  }

//  ProjectWithDependenciesFunction _wrapDependencyProcessor(
//          String description, ProjectWithDependenciesFunction processor) =>
//      (Project project, Iterable<Project> dependencies) async {
//    final taskDescription =
//        '$description for project ${project.name} with ${dependencies.length} dependencies';
//    _log.info('Executing command "$taskDescription"');
//    await processor(project, dependencies);
//    _log.finer('Completed command "$taskDescription"');
//  };

//  Future executeAll(Iterable<ProjectCommand> commands) =>
//      Future.forEach(commands, execute);
//  // TODO: this is the safest approach. It will execute each command from scratch
//  // reevaluating allProjects and reloading all projects for each command
//  // More efficient thought is if projects loaded once and then each command run
//  // on them in turn

  @override
  Future executeAll(CompositeProjectCommand composite,
      {CommandConcurrencyMode concurrencyMode: CommandConcurrencyMode.concurrentCommand}) async {
    // TODO: only serial supported for now
    return _executeSerially(composite);
//    if (concurrently) {
//      await _executeConcurrently(composite);
//    } else {
//      await _executeSerially(composite);
//    }
  }

  /////// BAD IDEA. Can't do this
//  Future _executeConcurrently(CompositeProjectCommand composite) async {
//    final wrappedCommand = projectCommandWithDependencies(composite.name,
//        (Project project, Iterable<Project> dependencies) async {
//      await Future.forEach(composite.commands, (ProjectCommand command) async {
//        if (command.function is ProjectWithDependenciesFunction) {
//          await command.function(project, dependencies);
//        } else if (command.function is ProjectFunction) {
//          await command.function(project);
//        } else {
//          throw new ArgumentError('Invalid function passed into execute');
//        }
//      });
//    });
//
//    await execute(wrappedCommand);
//  }

  Future _executeSerially(CompositeProjectCommand composite) async {
    _log.info('Executing composite command "${composite.name}"');
    final result = await Future.forEach(composite.commands, execute);
    _log.finer('Completed command "${composite.name}"');
    return result;
  }

  @override
  Future executeOn(ProjectCommand command, String projectName) async {
    final DependencyGraph graph =
        await getDependencyGraph(await _projectGroup.allProjects);
    final projectDependencies = graph.forProject(projectName);
    return await command.process(projectDependencies.project,
        dependencies: projectDependencies.dependencies);
  }

  @override
  Future executeOnGraph(ProjectDependencyGraphCommand command) async {
    final DependencyGraph graph =
        await getDependencyGraph(await _projectGroup.allProjects);
    return await command.process(graph, _projectGroup.containerDirectory);
  }
}

typedef Future CommandExecutorFunction(ProjectCommand command);

/// TODO: will need something like this.
/// - maintain queues per project
/// - commands always execute serially on a project
/// - add commands to queues according to concurrency mode
class ConcurrentCommandExecutor {
  Map<String, ProjectCommandQueue> _projectQueues;
  final CommandConcurrencyMode concurrencyMode;
  final ProjectGroup projectGroup;

  Iterable<Project> get projects => projectGroup.allProjects;
  Future<Iterable<ProjectDependencies>> get depthFirst async =>
      (await getDependencyGraph(projects)).depthFirst;

  Option<ProjectCommandQueue> getQueue(Project project) =>
      new Option(_projectQueues[project.name]);

  Future awaitQueuesEmpty() {
//    _projectQueues.values.((q) => q.queueIsEmpty)
  }

  Future execute(Iterable<ProjectCommand> commands) {
    // TODO: forEach won't work. In some cases need to wait till stuff finishes
    commands.forEach((command) async {
      final CommandConcurrencyMode mode = concurrencyMode.index <
              command.concurrencyMode.index
          ? concurrencyMode
          : command.concurrencyMode;

      switch (mode) {
        case CommandConcurrencyMode.serial:
          // depthFirst. Await completion
          final projectDeps = await depthFirst;
          await Future.forEach(projectDeps, (ProjectDependencies pd) async {
            final qOpt = getQueue(pd.project);
//            qOpt.map((q) )
            if (qOpt is Some) {
              // TODO: assuming has depends
              await qOpt.get().add(() =>
                  command.process(pd.project, dependencies: pd.dependencies));
            }
          });

          break;
        case CommandConcurrencyMode.concurrentProject:
        // add to all queues. Wait till all queues empty
        case CommandConcurrencyMode.concurrentCommand:
        // add to all queues and move to next command
        default:
          throw new StateError('unexpected concurrency mode: $mode');
      }
    });
  }
}

typedef ProjectCommandExecution();

class ProjectCommandQueue {
  final Queue<ProjectCommandExecution> _queue = new Queue();
  Option<ProjectCommandExecution> _pending = const None();
  final ControllableProperty<bool> _queueIsEmpty =
      new ControllableProperty(true);
  Property<bool> get queueIsEmpty => _queueIsEmpty.distinctProperty;

//  ProjectCommandQueue(this._executor);

  void add(ProjectCommandExecution command) {
    _queue.add(command);
    _queueIsEmpty.value = false;
    _check();
  }

  Future _check() async {
    if (_pending is None && _queue.isNotEmpty) {
      final command = _queue.removeFirst();
      _pending = new Some(command);
      // TODO: should we attempt to catch exceptions?
      await command();
      _check();
    } else if (_pending is None && _queue.isEmpty) {
      _queueIsEmpty.value = true;
    }
  }
}