# HomeServant MVP

## Rule: text must never be invisible

Every piece of rendered text needs an explicit, deliberately chosen color that is verified to contrast against the exact container/background it is drawn on — never rely on a widget's default text color, an inherited ambient style, or "it happened to look fine in one theme." This app has been repeatedly bitten by exactly this class of bug (raw `TextField`s left without a `style`, so they picked up whatever the ambient `Theme`/`ColorScheme` produced instead of this app's own navy-on-light convention).

Concretely:

- Never leave a `TextField`/`TextFormField` (or its `hintStyle`/`labelStyle`) without an explicit `style`/color when it sits inside a custom-colored container (a bottom sheet, a card, a filled input). If you can't immediately point to the exact color a piece of text will render in, that's the bug.
- When using `DashboardTheme` (`lib/models/dashboard_theme.dart`), treat `background`/`foreground`, `surface`/`onSurface`, and `accent`/`onAccent` as fixed pairs. Never draw `foreground` text on a `surface` container or `onSurface` text directly on `background` — each pair is only guaranteed to contrast against its own partner, and `background`/`foreground` flip per theme (e.g. Midnight's `background` is dark navy) while `surface`/`onSurface` stay a light-surface/navy-text pair in every theme.
- When giving a reusable field widget (`PillTextField`, `LabeledPillField`, `LabeledDropdownField`, etc.) a non-default `fillColor`, always pass the matching `textColor` explicitly alongside it — don't override one half of a color pair and leave the other on its default.
- Admin console screens use the static `AppColors`/`AppTextStyles` (navy text on white/off-white) — the same rule applies: any raw `TextField` there needs an explicit `style`/`labelStyle`/`hintStyle`, since the app's global theme (`AppTheme.light` / `ColorScheme.fromSeed`) is not guaranteed to match this app's own hardcoded palette.
- When adding a new `DashboardTheme` variant or a new themed container, sanity-check every text color drawn on it across *all* theme variants, not just whichever one you happened to be looking at while building the screen.

## Rule: a fix comes with a test, and nothing is pushed unchecked

Fixed bugs have kept coming back (Google sign-in, the date-of-birth calendar's invisible text) because nothing checked them after the fix. So:

- Every bug fix adds a test that fails without the fix and passes with it. Before pushing, confirm the test actually catches the bug (undo the fix, watch it fail, restore). Config-level fixes (`vercel.json`'s security policy, `web/index.html`) get a guard in `test/regression_guards_test.dart`.
- Before pushing, run what CI runs: `flutter analyze` and `flutter test` at the root (any analyzer `info` fails CI too), and in `backend/`: `npx tsc --noEmit -p tsconfig.json` and `npm test` (needs `TEST_DATABASE_URL` pointing at a disposable, migrated Postgres; see `backend/test/helpers.ts`). The SessionStart hook (`.claude/hooks/session-start.sh`) installs Flutter and the backend packages in Claude Code on the web sessions.
