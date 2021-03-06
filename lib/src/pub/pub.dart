// Copyright (c) 2015, Anders Holmgren. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library jefe.pub;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jefe/src/pub/pub_version.dart';
import 'package:logging/logging.dart';
import 'package:option/option.dart';
import 'package:path/path.dart' as p;

import '../util/process_utils.dart';

final Logger _log = new Logger('jefe.pub');

Future get(Directory projectDirectory) =>
    runCommand('pub', ['get'], processWorkingDir: projectDirectory.path);

Future test(Directory projectDirectory) async {
  if (await new Directory(p.join(projectDirectory.path, 'test')).exists()) {
    return runCommand('pub', ['run', 'test'],
        processWorkingDir: projectDirectory.path);
  }
}

Future publish(Directory projectDirectory) =>
    runCommand('pub', ['publish', '--force'],
        processWorkingDir: projectDirectory.path);

Future<Option<HostedPackageVersions>> fetchPackageVersions(String packageName,
    {Uri publishToUrl}) async {
  final baseUrl = publishToUrl?.toString() ?? 'https://pub.dartlang.org';

  final packageDetailsUrl = '$baseUrl/api/packages/$packageName';

  _log.finest('Attempting to fetch published versions from $packageDetailsUrl');

  final http.Response response = await http.get(packageDetailsUrl);

  _log.finest(
      'Received response code (${response.statusCode}) from $packageDetailsUrl');

  switch (response.statusCode) {
    case 200:
      _log.finer('Found published package versions. '
          'Assuming package $packageName is hosted');
      return new Some(
          new HostedPackageVersions.fromJson(JSON.decode(response.body)));

    case 404:
      _log.finer('Found NO published package versions. '
          'Assuming package $packageName is NOT hosted');
      return const None();

    default:
      throw new StateError('unexpected status code ${response.statusCode}');
  }
}
