// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project;

import 'dart:async';
import 'dart:io';
import 'impl/project_impl.dart';
import '../spec/jefe_spec.dart';
import 'core.dart';
import 'package:pubspec/pubspec.dart';
import 'package:analyzer/analyzer.dart';
import 'package:option/option.dart';

abstract class ProjectReference implements ProjectEntityReference<Project> {}

/// Represents a Dart Project versioned with Git. Provides access to the
/// [PubSpec] and the git repository
abstract class Project extends ProjectEntity {
  PubSpec get pubspec;
  ProjectIdentifier get id;
  Future<Option<CompilationUnit>> get compilationUnit;
  Future<Iterable<String>> get exportedDependencyNames;
  Future<Iterable<String>> get exportedDevDependencyNames;

  /// Installs a Project from the [gitUri] into the [parentDirectory]
  static Future<Project> install(
          Directory parentDirectory, String name, String gitUri) =>
      ProjectImpl.install(parentDirectory, name, gitUri);

  static Future<Project> load(Directory installDirectory) =>
      ProjectImpl.load(installDirectory);

  Future<String> get currentGitCommitHash;

  Future updatePubspec(PubSpec newSpec);
}
