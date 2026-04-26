/// Internal SDK endpoint configuration. Not exported — clients (who install
/// morphui from pub.dev) always hit the Morph SaaS. The only
/// override is `--dart-define=CHAMELEON_API_BASE_URL=...`, used by SDK
/// maintainers pointing at a local backend while iterating on the SDK
/// itself.
library;

const String _prodBaseUrl = 'https://api.morphui.dev';

const String _envOverride = String.fromEnvironment('CHAMELEON_API_BASE_URL');

String get kMorphApiBaseUrl =>
    _envOverride.isNotEmpty ? _envOverride : _prodBaseUrl;
