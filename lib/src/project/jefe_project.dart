// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.project.jefe;

import 'dart:async';

import 'package:jefe/src/project/project.dart';
import 'package:option/option.dart';

/// A [Project] managed by Jefe
abstract class JefeProject extends Project implements JefeProjectGraph {
  JefeProjectSet get directDependencies;
  Set<JefeProject> get indirectDependencies;
  Set<JefeProject> get allDependencies;
}

/// A graph of [JefeProject] ordered by their dependencies
abstract class JefeProjectGraph {
  /// Navigates the graph of [JefeProject] depthFirst such that those
  /// with no dependencies are returned first and those projects that are
  /// depended upon by other projects are returned before those projects
  Iterable<JefeProject> get depthFirst;

  Iterable<JefeProject> getDepthFirst(Set<JefeProject> visited);

  /// returns a [JefeProject] with matching name that is either this project
  /// or one of it's dependencies (direct or indirect)
  Option<JefeProject> getProjectByName(String projectName);

  /// Iterates over [depthFirst] invoking process for each
  Future processDepthFirst(
      process(JefeProject project, Iterable<JefeProject> dependencies));
}

/// A [Set] of [JefeProject] that supports [JefeProjectGraph] operations
abstract class JefeProjectSet implements Set<JefeProject>, JefeProjectGraph {}
