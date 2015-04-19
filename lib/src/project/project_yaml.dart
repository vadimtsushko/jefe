library devops.project.metadata.yaml;

import 'package:yaml/yaml.dart';
import 'dart:io';
import 'dart:async';
import '../spec/JefeSpec.dart';
import 'package:logging/logging.dart';

Logger _log = new Logger('devops.project.metadata.yaml');

/// Reads the [ProjectGroupMetaData] from the [File]
Future<ProjectGroupMetaData> readProjectGroupYaml(File projectGroupFile) async {
  final Map yaml = loadYaml(await projectGroupFile.readAsString());

  _log.finer('reading project.yaml $projectGroupFile');

  final Map projectGroupsMap = yaml['groups'] != null ? yaml['groups'] : {};

  final Map projectsMap = yaml['projects'] != null ? yaml['projects'] : {};

  final childProjectGroups = projectGroupsMap.keys
      .map((k) => new ProjectGroupRefImpl(k, projectGroupsMap[k]));

  final childProjects =
      projectsMap.keys.map((k) => new ProjectIdentifierImpl(k, projectsMap[k]));

  return new ProjectGroupMetaDataImpl(
      yaml['name'], childProjectGroups, childProjects);
}
