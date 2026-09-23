/// Base URL of the HomeServant API, e.g.
/// `flutter run --dart-define=API_BASE_URL=http://localhost:3000/api`.
/// Falls back to local dev so `flutter run`/`flutter test` without the
/// define still points somewhere sensible.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api',
);
