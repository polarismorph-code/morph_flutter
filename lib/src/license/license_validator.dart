import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/endpoints.dart';
import 'app_identity.dart';
import 'morph_plan.dart';

/// SDK version sent in the validate payload so the backend can deprecate
/// older clients gracefully. Bump this in lock-step with `pubspec.yaml`.
const String kMorphSdkVersion = '0.1.0';

/// Resolves a license key to a [MorphPlan] with three layers of
/// fallback so the host app never blocks on a bad network:
///   1. **Demo shortcut** — `cha-free-demo` resolves to FREE locally,
///      no HTTP at all.
///   2. **Hive cache (24h)** — every successful backend call is mirrored
///      to `cml_config`. We return cached results immediately on
///      subsequent boots and re-validate in the background.
///   3. **Network call** — `POST /api/flutter/license/validate`. 8s
///      timeout. On any failure we fall back to the cache; if the cache
///      is also empty, we degrade to FREE.
///
/// The validator is single-shot per provider lifetime — call [validate]
/// once at boot, read the resolved [plan] thereafter.
class LicenseValidator {
  final String licenseKey;

  MorphPlan _plan = MorphPlan.free;
  bool _validated = false;
  bool _isValidating = false;
  String? _error;

  LicenseValidator({required this.licenseKey});

  MorphPlan get plan => _plan;
  bool get isValidated => _validated;
  bool get hasError => _error != null;
  String? get error => _error;

  // Hive box used for tiny scalar caches — separate from BehaviorDB so
  // the validator can run BEFORE BehaviorDB.init().
  static const String _boxName = 'cml_config';
  static const String _planKey = 'cml_license_plan';
  static const String _validatedAtKey = 'cml_license_validated_at';
  static const Duration _cacheTtl = Duration(hours: 24);

  Future<MorphPlan> validate() async {
    if (_isValidating) return _plan;
    _isValidating = true;

    // Demo shortcut — no network, no cache.
    if (licenseKey == 'cha-free-demo') {
      _plan = MorphPlan.free;
      _validated = true;
      _isValidating = false;
      return _plan;
    }

    // Make sure Hive is up before touching the cache box. `initFlutter`
    // is idempotent; calling it again is a no-op once initialized.
    try {
      await Hive.initFlutter();
      if (!Hive.isBoxOpen(_boxName)) await Hive.openBox(_boxName);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🦎 Morph validator: Hive init failed ($e)');
      }
    }

    final cached = _readCachedPlan();
    if (cached != null) {
      _plan = cached;
      _validated = true;
      _isValidating = false;
      // Refresh in the background — the user already got the cached
      // answer, but the next boot will see the latest.
      unawaited(_revalidateInBackground());
      return _plan;
    }

    try {
      _plan = await _validateWithBackend();
      _validated = true;
      _error = null;
      await _writeCachedPlan(_plan);
    } catch (e) {
      _error = e.toString();
      _plan = _readCachedPlan() ?? MorphPlan.free;
      assert(() {
        debugPrint(
          '🦎 Morph: license validation failed — $e\n'
          'Falling back to ${_plan.label} plan.',
        );
        return true;
      }());
    }

    _isValidating = false;
    return _plan;
  }

  Future<MorphPlan> _validateWithBackend() async {
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'unknown';
    // Resolve the package id BEFORE the request so the backend's origin
    // guard can match against allowed_packages[platform]. First call is
    // cheap on the platform channel, subsequent calls are synchronous.
    final appId = await AppIdentity.resolve();
    final uri =
        Uri.parse('$kMorphApiBaseUrl/api/flutter/license/validate');
    final res = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'licenseKey': licenseKey,
            'appId': appId,
            'platform': platform,
            'sdkVersion': kMorphSdkVersion,
          }),
        )
        .timeout(const Duration(seconds: 8));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return MorphPlan.fromString(data['plan'] as String?);
    }
    if (res.statusCode == 401) throw Exception('Invalid license key');
    if (res.statusCode == 402) throw Exception('License expired');
    throw Exception('Validation failed: ${res.statusCode}');
  }

  MorphPlan? _readCachedPlan() {
    if (!Hive.isBoxOpen(_boxName)) return null;
    final box = Hive.box(_boxName);
    final planStr = box.get(_planKey) as String?;
    final cachedAt = box.get(_validatedAtKey) as int?;
    if (planStr == null || cachedAt == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
    if (age > _cacheTtl.inMilliseconds) return null;
    return MorphPlan.fromString(planStr);
  }

  Future<void> _writeCachedPlan(MorphPlan plan) async {
    if (!Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box(_boxName);
    await box.put(_planKey, plan.name);
    await box.put(_validatedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Fire-and-forget refresh after a cache hit. Updates the cached plan
  /// silently if the backend now reports a different tier (e.g. user
  /// upgraded since last boot).
  Future<void> _revalidateInBackground() async {
    try {
      final fresh = await _validateWithBackend();
      if (fresh != _plan) {
        _plan = fresh;
        await _writeCachedPlan(fresh);
        assert(() {
          debugPrint(
            '🦎 Morph: plan updated to ${fresh.label} '
            '(background revalidation)',
          );
          return true;
        }());
      }
    } catch (_) {
      // Silent — we already returned the cached answer to the user.
    }
  }
}
