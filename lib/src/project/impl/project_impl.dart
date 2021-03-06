// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.impl;

import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:git/git.dart';
import 'package:jefe/src/project/impl/project_group_impl.dart';
import 'package:jefe/src/project_commands/project_command.dart'
    show executeTask;
import 'package:jefe/src/pub/pub_version.dart';
import 'package:logging/logging.dart';
import 'package:option/option.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec/pubspec.dart';

import '../../git/git.dart' as git;
import '../../pub/pub.dart' as pub;
import '../../spec/jefe_spec.dart';
import '../project.dart';
import 'core_impl.dart';

Logger _log = new Logger('jefe.project.impl');

class ProjectImpl extends ProjectEntityImpl implements Project {
  PubSpec _pubspec;

  PubSpec get pubspec => _pubspec;

  String get name => pubspec.name;

  ProjectIdentifier get id => new ProjectIdentifier(name, gitUri);

  final HostedMode _hostedMode;

  HostedMode get _pubSpecHostedMode =>
      pubspec.publishTo != null ? HostedMode.hosted : HostedMode.inferred;

  @override
  HostedMode get hostedMode => _hostedMode ?? _pubSpecHostedMode;

  ProjectImpl(String gitUri, Directory installDirectory, this._pubspec,
      this._hostedMode)
      : super(gitUri, installDirectory);

  static Future<ProjectImpl> install(
      Directory parentDir, String name, String gitUri,
      {bool updateIfExists, HostedMode hostedMode}) async {
    _log.info('installing project $name from $gitUri into $parentDir');

    final projectParentDir = await parentDir.create(recursive: true);

    final GitDir gitDir = await git.cloneOrPull(
        gitUri,
        projectParentDir,
        new Directory(p.join(projectParentDir.path, name)),
        git.OnExistsAction.ignore);

    final installDirectory = new Directory(gitDir.path);
    return new ProjectImpl(
        gitUri,
        installDirectory,
        await PubSpec.load(installDirectory),
        hostedMode ?? HostedMode.inferred);
  }

  static Future<Project> load(Directory installDirectory,
      {HostedMode hostedMode}) async {
    _log.info('loading project from install directory $installDirectory');
    final GitDir gitDir = await GitDir.fromExisting(installDirectory.path);

    final PubSpec pubspec = await PubSpec.load(installDirectory);

    final String gitUri = await git.getOriginOrFirstRemote(gitDir);
    return new ProjectImpl(
        gitUri, installDirectory, pubspec, hostedMode ?? HostedMode.inferred);
  }

  @override
  Future updatePubspec(PubSpec newSpec) async {
    _log.info('Updating pubspec for project ${name}');
    await newSpec.save(installDirectory);
    _pubspec = newSpec;
    _log.finest('Finished Updating pubspec for project ${name}');
  }

  @override
  Future<String> get currentGitCommitHash async =>
      git.currentCommitHash(await gitDir);

  @override
  Future<Option<CompilationUnit>> get compilationUnit async {
    final mainLibraryPath =
        p.join(installDirectory.path, 'lib', '${name}.dart');
    final exists = await new File(mainLibraryPath).exists();
    return exists ? new Some(parseDartFile(mainLibraryPath)) : const None();
  }

  String toString() => 'Project($name, $gitUri)';

  @override
  Future<Iterable<String>> get exportedDependencyNames async =>
      _exportedDependencyNames(pubspec.dependencies.keys);

  @override
  Future<Iterable<String>> get exportedDevDependencyNames async =>
      _exportedDependencyNames(pubspec.devDependencies.keys);

  @override
  Future<Set<String>> get exportedPackageNames async {
    final Iterable<Directive> exports = (await compilationUnit)
        .map /**<Iterable<Directive>>*/ (
            (cu) => cu.directives.where((d) => d is ExportDirective))
        .getOrDefault(<Directive>[]) as Iterable<Directive>;

    final exportedPackageNames = await exports
        .map((exp) => (exp as ExportDirective).uri.stringValue)
        .where((uri) => uri.startsWith('package:'))
        .map((String uri) => uri.substring('package:'.length, uri.indexOf('/')))
        .toSet();
    return exportedPackageNames;
  }

  @override
  Future<Option<Version>> get latestTaggedGitVersion async {
    final _taggedVersions = await taggedGitVersions;

    final Option<Version> latestTaggedVersionOpt = _taggedVersions.isNotEmpty
        ? new Some(_taggedVersions.last)
        : const None();
    return latestTaggedVersionOpt;
  }

  @override
  Future<Iterable<Version>> get taggedGitVersions => executeTask(
      'fetch git release version tags',
      () async => git.gitFetchVersionTags(await gitDir));

  @override
  Future<Option<Version>> get latestPublishedVersion async {
    return (await publishedVersions).map(
            (HostedPackageVersions versions) => versions.versions.last.version)
        as Option<Version>;
  }

  @override
  Future<Option<HostedPackageVersions>> get publishedVersions async =>
      executeTask(
          'fetch package versions',
          () async =>
              pub.fetchPackageVersions(name, publishToUrl: pubspec.publishTo));

  @override
  Future<ProjectVersions> get projectVersions async {
    final _latestPublishedVersionFuture = latestPublishedVersion;
    final isHostedFuture = _latestPublishedVersionFuture.then((o) {
      final hasBeenPublished = o is Some;

      final _hostedMode = hostedMode != HostedMode.inferred
          ? hostedMode
          : hasBeenPublished ? HostedMode.hosted : HostedMode.notHosted;

      return _hostedMode == HostedMode.hosted;
    });
    final versions = await Future.wait([
      latestTaggedGitVersion,
      _latestPublishedVersionFuture,
      isHostedFuture
    ]);
    return new ProjectVersions(pubspec.version, versions[0] as Option<Version>,
        versions[1] as Option<Version>, versions[2] as bool);
  }

//  @override
//  Future<bool> get hasChangesSinceLatestTaggedVersion async=>
//     hasChangesSince(gitDir, await latestTaggedGitVersion);

  Future<Iterable<String>> _exportedDependencyNames(
      Iterable<String> dependencyNames) async {
    final exported = await exportedPackageNames;

    return dependencyNames.where((n) => exported.contains(n));
  }

  @override
  bool operator ==(other) =>
      other is ProjectImpl &&
      other.runtimeType == runtimeType &&
      other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class ProjectReferenceImpl implements ProjectReference {
  final ProjectGroupImpl parent;
  final ProjectIdentifier ref;
  ProjectReferenceImpl(this.parent, this.ref);

  @override
  Future<Project> get() => parent.getChildProject(name, gitUri);

  @override
  String get gitUri => ref.gitUri;

  @override
  String get name => ref.name;
}
