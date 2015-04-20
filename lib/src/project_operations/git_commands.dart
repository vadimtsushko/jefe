library jefe.project.operations.git;

import 'package:jefe/src/project_operations/project_command.dart';
import 'impl/git_commands_impl.dart';

abstract class GitCommands {
  factory GitCommands() = GitCommandsImpl;

  ProjectCommand commit(String message);

  ProjectCommand push();

  ProjectCommand checkout(String branchName);
}
