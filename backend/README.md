# HomeServant API

NestJS + Prisma + PostgreSQL backend for the HomeServant Flutter app (mobile
and web). Covers auth, user profiles, properties, bookings, and favorites —
the pieces the current app screens actually call. See **Not built yet**
below for what's intentionally out of scope for this first pass.

## Local setup

1. Install Postgres locally, or point `DATABASE_URL` at any Postgres
   instance (Render's, Supabase's, whatever — this is a plain Postgres
   schema, nothing Render-specific about the data layer).
2. `cp .env.example .env` and fill in `DATABASE_URL` plus two random
   secrets (`openssl rand -hex 32` twice) for `JWT_ACCESS_SECRET` /
   `JWT_REFRESH_SECRET`.
3. `npm install`
4. `npm run prisma:migrate` — creates the database schema.
5. `npm run start:dev` — API is at `http://localhost:3000/api`, restarts on
   file changes.

With `OTP_PROVIDER=console` (the default), signup/login verification codes
print to the server's terminal instead of being emailed/texted — check
there while testing locally.

## Deploying to Render

1. Push this repo to GitHub/GitLab (Render deploys from a git remote).
2. In the Render dashboard: **New > Blueprint**, point it at this repo.
   `render.yaml` provisions the web service and a free Postgres database
   together, and wires `DATABASE_URL` from the database to the API
   automatically.
3. Once it's up, set `CORS_ORIGINS` on the service to your actual deployed
   Flutter web origin (the free-tier default only allows
   `http://localhost:8765`, the port used for local `flutter run -d chrome`
   testing).
4. The free Postgres plan expires after 30 days unless upgraded — fine for
   getting the wiring right, not for anything real users touch. Check
   Render's current pricing page before launch; their free-tier terms
   change.
5. Free web services also spin down after 15 minutes idle and take
   30-50s to cold-start the next request. That's a bad experience for
   login/OTP and would break a persistent chat connection once that's
   built — move to a paid instance before real users depend on this.

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

Everything else (`/api/users/me`, `/api/properties`, `/api/bookings`,
`/api/favorites`) expects `Authorization: Bearer <accessToken>` except
`GET /api/properties` and `GET /api/properties/:id`, which are public so
the tenant browse feed doesn't require login.

## Wiring this into the Flutter app

Nothing on the client calls this yet — `AppState` and the mock data lists
(`mockProperties`, etc.) are still what every screen reads from. To
actually connect them:

1. Add an HTTP client (`dio` is the common choice) with the API's base URL
   read from `--dart-define=API_BASE_URL=...` so dev/staging/prod builds
   can point at different deployments.
2. Replace `AppState`'s local-only signup/login with real calls to
   `/auth/*`, storing the returned tokens in `flutter_secure_storage`
   (not `SharedPreferences` — that's currently storing the raw password,
   which should be deleted from local state entirely once this lands).
3. Swap `mockProperties` reads for `GET /properties` calls, and the
   landlord's `AppState.landlordProperties` list for real
   `POST /properties` calls from `LandlordAddPropertyScreen`.
4. Swap the Bookings screen's in-memory `_bookings`/`_rent` lists for
   `GET /bookings/landlord` and `PATCH /bookings/:id/respond`.

## Not built yet

Scoped out of this pass on purpose, to ship something real rather than a
half-built everything:

- **Chat** — the Messages screens are still fully mocked. Needs a
  real-time layer (Socket.IO on its own Render service, or a managed
  option like Ably/Pusher) plus `Message`/`Thread` models.
- **Marketplace** — vendors, products, orders, and payments aren't
  modelled at all yet.
- **Tenancy agreements** — no PDF generation or storage.
- **Payments** — no Paystack/Flutterwave integration for rent or
  marketplace checkout.
- **File uploads** — DTOs accept an `imageUrl` string, but there's no
  upload endpoint yet. Add object storage (Cloudflare R2 or S3) and a
  signed-upload-URL endpoint before wiring the Flutter app's image
  pickers to this API.
- **Real OTP delivery** — `OTP_PROVIDER=console` only. Implement
  `OtpProvider` (see `src/otp/otp-provider.interface.ts`) for Termii (SMS)
  and an email provider before this touches real users.
- **Reviews/ratings** — the Flutter `Property` model has a `rating`
  field; there's no review system backing it here yet.
