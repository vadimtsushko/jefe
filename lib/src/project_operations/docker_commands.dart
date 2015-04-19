library devops.project.operations.docker;

import 'package:devops/src/project_operations/project_command.dart';
import 'dart:io';
import 'impl/docker_commands_impl.dart';

abstract class DockerCommands {
  factory DockerCommands() = DockerCommandsImpl;

  /// Generates a Dockerfile based on the provided [serverProjectName].
  /// If these projects have path dependencies on other projects
  /// managed by jefe then those dependent projects are added first
  ProjectDependencyGraphCommand generateDockerfile(
      String serverProjectName, String clientProjectName,
      {Directory outputDirectory, String dartVersion: 'latest',
      Map<String, dynamic> environment: const {},
      Iterable<int> exposePorts: const [],
      Iterable<String> entryPointOptions: const [],
      bool omitClientWhenPathDependencies: true, bool setupForPrivateGit: true,
      String targetRootPath: '/app'});

  ProjectDependencyGraphCommand generateProductionDockerfile(
      String serverProjectName, String clientProjectName, {String serverGitRef,
      String clientGitRef, Directory outputDirectory,
      String dartVersion: 'latest', Map<String, dynamic> environment: const {},
      Iterable<int> exposePorts: const [],
      Iterable<String> entryPointOptions: const [],
      String targetRootPath: '/app'});
}