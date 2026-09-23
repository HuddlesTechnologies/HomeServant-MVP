# HomeServant API

NestJS + Prisma + PostgreSQL (Supabase) backend for the HomeServant Flutter
app (mobile and web). Covers auth, user profiles, properties, bookings,
favorites, file uploads, reviews, and chat — the pieces the current app
screens actually call. See **Not built yet** below for what's intentionally
out of scope for this pass.

## Local setup

1. Create a free project at [supabase.com](https://supabase.com). Project
   Settings > Database gives you the pooled and direct connection
   strings; Project Settings > API gives you the URL and service role
   key.
2. `cp .env.example .env` and fill in `DATABASE_URL`, `DIRECT_URL`,
   `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, plus two random secrets
   (`openssl rand -hex 32` twice) for `JWT_ACCESS_SECRET` /
   `JWT_REFRESH_SECRET`.
3. In Supabase Storage, create a bucket named `homeservant-uploads`
   (matches `SUPABASE_STORAGE_BUCKET`'s default) and mark it **public** —
   uploaded property/profile images are read via their public URL
   directly, no signed read needed.
4. `npm install`
5. `npm run prisma:migrate` — creates the database schema.
6. `npm run start:dev` — API is at `http://localhost:3000/api`, restarts on
   file changes.

With `OTP_PROVIDER=console` (the default), signup/login verification codes
print to the server's terminal instead of being emailed/texted — check
there while testing locally.

## Deploying to Render

The database and storage live on Supabase; Render only runs the API
container.

1. Push this repo to GitHub/GitLab (Render deploys from a git remote).
2. In the Render dashboard: **New > Blueprint**, point it at this repo.
   `render.yaml` provisions the web service.
3. `render.yaml` leaves `DATABASE_URL`, `DIRECT_URL`, `SUPABASE_URL`, and
   `SUPABASE_SERVICE_ROLE_KEY` unset (`sync: false`) — fill these in by
   hand on the service's **Environment** tab in Render, using the values
   from your Supabase project (same ones as in local `.env`, see above).
4. Once it's up, set `CORS_ORIGINS` on the service to your actual deployed
   Flutter web origin (the free-tier default only allows
   `http://localhost:8765`, the port used for local `flutter run -d chrome`
   testing).
5. Supabase's free plan pauses a project after a week with no API
   requests (unpauses on the next request/dashboard visit, but the first
   request after a pause is slow) and caps the database at 500MB — fine
   for getting the wiring right, not for anything real users touch. Check
   Supabase's current pricing page before launch; free-tier terms change.
6. Render's free web service tier also spins down after 15 minutes idle
   and takes 30-50s to cold-start the next request. That's a bad
   experience for login/OTP and would break a persistent chat connection
   once that's built — move to a paid instance before real users depend
   on this.

The Dockerfile runs `prisma migrate deploy` on every boot, so pushing a new
migration and redeploying is enough to apply it — no separate migration
step needed.

## API shape

Every route is prefixed `/api`. Auth:

- `POST /api/auth/signup` — creates the user (unverified), sends a 4-digit
  code (matches the Flutter client's 4-box OTP input).
- `POST /api/auth/verify-signup` — verifies that code, returns
  `{ accessToken, refreshToken, user }`.
- `POST /api/auth/login` — returns tokens directly, or
  `{ requiresTwoFactor: true, email }` if the account has 2FA on.
- `POST /api/auth/verify-2fa` — completes a 2FA login the same way
  verify-signup completes signup.
- `POST /api/auth/refresh` — rotates a refresh token for a new pair; the
  old one is revoked the moment this succeeds, so a leaked-and-replayed
  refresh token stops working as soon as the real client refreshes.
- `POST /api/auth/logout` — revokes one refresh token.
- `PATCH /api/auth/password` (authenticated) with `{ currentPassword,
  newPassword }` — also revokes every other refresh token, so changing
  your password signs other sessions out.

Everything else (`/api/users/me`, `/api/properties`, `/api/bookings`,
`/api/favorites`, `/api/uploads`, `/api/reviews`, `/api/threads`) expects
`Authorization: Bearer <accessToken>` except `GET /api/properties`,
`GET /api/properties/:id`, and `GET /api/reviews`, which are public so the
tenant browse feed doesn't require login.

### File uploads

`POST /api/uploads/sign` with `{ fileName, folder }` (`folder` is
`"properties"` or `"profile-photos"`) returns a one-time
`{ path, signedUrl, token, publicUrl }`. The client `PUT`s the raw file
bytes to `signedUrl` (`Content-Type` matching the file), then saves
`publicUrl` on the property (`imageUrl`/`galleryUrls`) or the user's
`profilePhotoUrl` via the existing update endpoints — this API never
receives the file itself, Supabase Storage does.

### Reviews

`GET /api/reviews?propertyId=` lists a property's reviews (public).
`GET /api/reviews/mine` (authenticated) lists every review the caller has
left, across properties.
`POST /api/reviews` (tenant only) upserts the caller's review for
`{ propertyId, rating, comment? }` — resubmitting updates the existing one
rather than erroring, since there's a one-review-per-tenant-per-property
constraint. `properties.avgRating`/`reviewCount` on every property response
are computed from this table, not stored on `Property` itself.

### Chat

- `GET /api/threads` — the caller's conversations, each with the other
  participant(s), the property it's about (if any), the last message, and
  an unread count.
- `POST /api/threads` with `{ recipientId, propertyId? }` — opens a thread,
  reusing an existing one between the same two people about the same
  property instead of duplicating it.
- `GET /api/threads/:id/messages` (optional `?before=<ISO timestamp>` to
  page backwards) / `POST /api/threads/:id/messages` with `{ body }`.
- `PATCH /api/threads/:id/read` — marks the other participant's messages
  as read.

Messages are persisted here, not on Supabase Realtime directly — the
Flutter client currently polls (refetch on screen focus / after sending)
rather than holding a live subscription. Supabase Realtime's Postgres
change feed is the natural next step for push delivery, but it authorizes
subscribers via Supabase Auth (`auth.uid()` in Row Level Security policies),
and this API has its own JWT auth instead — wiring it up means either
switching auth to Supabase Auth, or issuing this API's access tokens signed
with Supabase's own JWT secret so `auth.jwt()` resolves correctly in RLS.
Neither is done here; treat it as a deliberate follow-up, not an oversight.

## Wiring this into the Flutter app

The client's `lib/api/` layer (`ApiClient` + one repository per resource —
`AuthRepository`, `PropertiesRepository`, `BookingsRepository`,
`FavoritesRepository`, `ReviewsRepository`, `ChatRepository`,
`UploadsRepository`, `UsersRepository`) calls every endpoint above, with
access/refresh tokens in `flutter_secure_storage` (never `SharedPreferences`)
and the base URL read from `--dart-define=API_BASE_URL=...`. `lib/state/app_state.dart`
owns the signed-in session and the live lists screens read from
(`properties`, `landlordProperties`, `favoriteProperties`, `myBookings`,
`landlordBookings`, `rentalHistory`) — it holds no mock/seed data. Device-only
preferences (theme, notification toggles, app lock) still live in
`SharedPreferences`, since they have no server model.

## Not built yet

Scoped out of this pass on purpose, to ship something real rather than a
half-built everything:

- **Marketplace** — vendors, products, orders, and payments aren't
  modelled at all yet; the Flutter Marketplace screens are still fully
  mocked and have their own separate vendor-auth flow this API doesn't
  cover.
- **Tenancy agreement storage** — PDF generation is client-side only
  (`lib/features/dashboard/legal/tenancy_agreement_pdf.dart`); nothing
  persists the generated document server-side yet.
- **Payments** — no Paystack/Flutterwave integration for rent or
  marketplace checkout. Needs a real merchant account and API keys.
- **Real OTP delivery** — `OTP_PROVIDER=console` only. Implement
  `OtpProvider` (see `src/otp/otp-provider.interface.ts`) for Termii (SMS)
  and an email provider before this touches real users. Needs a real
  provider account and API key.
- **Live chat delivery** — see the Chat section above; messages persist
  and the client polls, but there's no Realtime/WebSocket push yet.
- **KYC / identity verification** — the signup flow's "means of
  identification" step (NIN, driver's license, etc.) and the landlord's
  certificate-of-ownership upload are UI-only; nothing about them reaches
  this API. There's no verification-document model to add them to yet.
- **Email/account changes** — `EditProfileScreen` shows the account email
  but doesn't let it be changed (no rename-email endpoint — changing the
  login identifier usually wants re-verification, deliberately left out
  of this pass). Password changes go through `PATCH /api/auth/password`
  instead, from Settings.
