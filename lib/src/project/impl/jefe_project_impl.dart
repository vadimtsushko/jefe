// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.jefe.impl;

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:jefe/src/project/impl/project_impl.dart';
import 'package:jefe/src/project/jefe_project.dart';
import 'package:jefe/src/project/project.dart';
import 'package:logging/logging.dart';
import 'package:option/option.dart';
import 'package:pubspec/pubspec.dart';
import 'package:quiver/iterables.dart';
import 'package:jefe/src/project/git_commands.dart';
import 'package:jefe/src/project/impl/git_commands_impl.dart';

Logger _log = new Logger('jefe.project.jefe.impl');

class JefeProjectImpl extends ProjectImpl
    with _JefeProjectGraphMixin
    implements JefeProject, JefeProjectGraph {
  @override
  final JefeProjectSet directDependencies;

  @override
  Set<JefeProject> get allDependencies =>
      getDepthFirst(new Set<JefeProject>()).toSet();

  @override
  Set<JefeProject> get indirectDependencies =>
      allDependencies.difference(directDependencies);

  JefeProjectImpl(this.directDependencies, String gitUri,
      Directory installDirectory, PubSpec pubspec, HostedMode hostedMode)
      : super(gitUri, installDirectory, pubspec, hostedMode);

  JefeProjectImpl.from(Set<JefeProject> directDependencies, Project project)
      : this(directDependencies, project.gitUri, project.installDirectory,
            project.pubspec, project.hostedMode);

  @override
  Iterable<JefeProject> getDepthFirst(Set<JefeProject> visited) {
    final children = directDependencies.getDepthFirst(visited);

    Iterable<JefeProject> us() sync* {
      if (!visited.contains((this))) {
        visited.add(this);
        yield this;
      }
    }

    return concat(<Iterable<JefeProject>>[children, us()])
        as Iterable<JefeProject>;
  }

  @override
  Option<JefeProject> getProjectByName(String projectName) =>
      name == projectName
          ? new Some<JefeProject>(this)
          : directDependencies.getProjectByName(projectName);

  @override
  GitCommands get git => new GitCommandsImpl(this);
}

class JefeProjectSetImpl extends DelegatingSet<JefeProject>
    with _JefeProjectGraphMixin
    implements JefeProjectSet {
  JefeProjectSetImpl(Set<JefeProject> base) : super(base);

  Option<JefeProject> getProjectByName(String projectName) =>
      map/*<Option<JefeProject>>*/((c) => c.getProjectByName(projectName))
          .firstWhere((o) => o is Some, orElse: () => const None())
      as Option<JefeProject>;

  Iterable<JefeProject> getDepthFirst(Set<JefeProject> visited) =>
      expand/*<JefeProject>*/((n) => n.getDepthFirst(visited))
      as Iterable<JefeProject>;
}

abstract class _JefeProjectGraphMixin implements JefeProjectGraph {
  Iterable<JefeProject> get depthFirst => getDepthFirst(new Set<JefeProject>());

  Iterable<JefeProject> _filteredDepthFirst(ProjectFilter filter) =>
      depthFirst.where(filter ?? _noOpFilter);

  Future/*<T>*/ processDepthFirst/*<T>*/(ProjectFunction/*<T>*/ command,
      {ProjectFilter filter, Combiner/*<T>*/ combine}) async {
    return await new Stream<JefeProject>.fromIterable(
            _filteredDepthFirst(filter))
        .asyncMap((JefeProject p) => command(p))
        .reduce(combine ?? _takeLast) as Future/*<T>*/;
//    return await Future.forEach(
//        _filteredDepthFirst(filter), (JefeProject p) => command(p));
  }

  Future/*<T>*/ processAllConcurrently/*<T>*/(ProjectFunction/*<T>*/ command,
      {ProjectFilter filter, Combiner/*<T>*/ combine}) async {
    return new Stream/*<T>*/ .fromFutures(
            _filteredDepthFirst(filter).map/*<Future<T>>*/(command))
        .reduce(combine ?? _takeLast) as Future/*<T>*/;
//    return (await Future.wait(_filteredDepthFirst(filter).map(command)))
//        .reduce(combine ?? _takeLast);
  }

  Future/*<T>*/ processAllSerially/*<T>*/(ProjectFunction/*<T>*/ command,
          {ProjectFilter filter, Combiner/*<T>*/ combine}) =>
      processDepthFirst(command, filter: filter, combine: combine);
}

bool _noOpFilter(Project p) => true;

/*=T*/ _takeLast/*<T>*/(/*=T*/ value, /*=T*/ element) => element;
