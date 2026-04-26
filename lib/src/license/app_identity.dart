import 'package:package_info_plus/package_info_plus.dart';

/// Source of the host app's package identifier — sent on every backend
/// call so the server can enforce the license's `allowed_packages`
/// binding (anti-key-sharing).
///
/// Resolves to:
///   • iOS     → CFBundleIdentifier   (e.g. `com.example.app`)
///   • Android → applicationId        (e.g. `com.example.app`)
///
/// Resolved exactly once per app process. The resolved id is then
/// available synchronously to callers that need to inject it into a
/// network payload (validator, theme adapter, analytics reporter, …).
class AppIdentity {
  static String? _cached;

  /// Reads the package id from [PackageInfo] and caches it. Safe to call
  /// many times — only the first call hits the platform channel. Returns
  /// the resolved id (also stored in [cachedOrEmpty]).
  static Future<String> resolve() async {
    if (_cached != null) return _cached!;
    final info = await PackageInfo.fromPlatform();
    _cached = info.packageName;
    return _cached!;
  }

  /// Synchronous accessor for the cached id. Returns the empty string
  /// when [resolve] hasn't completed yet — backend will reject the call
  /// with `LICENSE_ORIGIN_MISMATCH` in that edge case, which is
  /// preferable to silently passing a stale or wrong id.
  static String get cachedOrEmpty => _cached ?? '';
}
