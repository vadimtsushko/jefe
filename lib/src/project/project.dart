// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project;

import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:jefe/src/pub/pub_version.dart';
import 'package:option/option.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec/pubspec.dart';

import '../spec/jefe_spec.dart';
import 'core.dart';
import 'impl/project_impl.dart';

abstract class ProjectReference implements ProjectEntityReference<Project> {}

/// Represents a Dart Project versioned with Git. Provides access to the
/// [PubSpec] and the git repository
abstract class Project implements ProjectEntity {
  PubSpec get pubspec;
  ProjectIdentifier get id;
  Future<Option<CompilationUnit>> get compilationUnit;
  Future<Set<String>> get exportedPackageNames;
  Future<Iterable<String>> get exportedDependencyNames;
  Future<Iterable<String>> get exportedDevDependencyNames;
  HostedMode get hostedMode;

  Future<Option<Version>> get latestTaggedGitVersion;
  Future<Iterable<Version>> get taggedGitVersions;

  Future<Option<Version>> get latestPublishedVersion;
  Future<Option<HostedPackageVersions>> get publishedVersions;

  /// Fetches versions concurrently
  Future<ProjectVersions> get projectVersions;

  /// Installs a Project from the [gitUri] into the [parentDirectory]
  static Future<Project> install(
          Directory parentDirectory, String name, String gitUri) =>
      ProjectImpl.install(parentDirectory, name, gitUri);

  static Future<Project> load(Directory installDirectory) =>
      ProjectImpl.load(installDirectory);

  Future<String> get currentGitCommitHash;

  Future updatePubspec(PubSpec newSpec);
}

enum HostedMode { hosted, notHosted, inferred }

class ProjectVersions {
  final Version pubspecVersion;
  final Option<Version> taggedGitVersion;
  final Option<Version> publishedVersion;

  bool get hasBeenGitTagged => taggedGitVersion is Some;
  bool get hasBeenPublished => publishedVersion is Some;

  final bool isHosted; // hmmm doesn't make sense in ProjectVersions2

  ProjectVersions(this.pubspecVersion, this.taggedGitVersion,
      this.publishedVersion, this.isHosted);

  String toString() => 'pubspec version: $pubspecVersion; '
      'tagged version: $taggedGitVersion; '
      'published version: $publishedVersion';
}

class ProjectStatus {
  final ProjectVersions versions;
  final bool hasChangesSinceLastGitVersion;

  ProjectStatus(this.versions, this.hasChangesSinceLastGitVersion);
}
