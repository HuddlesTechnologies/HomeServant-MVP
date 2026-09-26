// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// This file only reaches the web compile target via the `dart.library.html`
// conditional import in token_storage.dart/app_state.dart — never bundled
// into a mobile/desktop build.
import 'dart:html' as html;

/// Backed by `window.sessionStorage`, not `localStorage` — deliberately.
/// `localStorage` is shared by every tab/window open on the same origin, so
/// two different users signed in from two tabs on the same browser (or a
/// stale tab left open after someone else logs in) would silently read and
/// overwrite each other's tokens/prefs. `sessionStorage` is isolated per
/// tab, so each tab keeps its own signed-in identity.
String? read(String key) => html.window.sessionStorage[key];

void write(String key, String value) => html.window.sessionStorage[key] = value;

void remove(String key) => html.window.sessionStorage.remove(key);
