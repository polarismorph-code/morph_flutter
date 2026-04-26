import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// In-memory `path_provider` stub so `Hive.initFlutter()` resolves to a
/// temp directory during widget tests (no platform channels).
class FakePathProvider extends PathProviderPlatform {
  final Directory dir;
  FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
  @override
  Future<String?> getTemporaryPath() async => dir.path;
  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

/// Allocates a fresh temp dir + wires the `path_provider` stub. Returns
/// the directory so the caller can wipe it in `tearDownAll`.
Future<Directory> setUpFakePathProvider({String prefix = 'cml_test'}) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  PathProviderPlatform.instance = FakePathProvider(dir);
  return dir;
}

/// Closes Hive + deletes the temp dir. Pair with [setUpFakePathProvider]
/// in `tearDownAll`.
Future<void> tearDownFakePathProvider(Directory dir) async {
  await Hive.close();
  if (dir.existsSync()) await dir.delete(recursive: true);
}
