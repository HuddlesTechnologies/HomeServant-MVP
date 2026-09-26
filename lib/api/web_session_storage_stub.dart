/// Non-web fallback for [web_session_storage_web.dart] — never actually
/// invoked (every call site guards with `kIsWeb` first), but required so
/// the conditional import resolves to *something* on platforms where
/// `dart:html` doesn't exist.
String? read(String key) => throw UnsupportedError('web only');
void write(String key, String value) => throw UnsupportedError('web only');
void remove(String key) => throw UnsupportedError('web only');
