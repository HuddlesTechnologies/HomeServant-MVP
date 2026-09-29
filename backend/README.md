# HomeServant API

NestJS 11 + Prisma 7 + PostgreSQL (Supabase) backend for the HomeServant
Flutter app (web and mobile), deployed on Render. It covers:

- **Accounts:** email + password with email codes and optional two-factor,
  Google sign-in (never for admins), profiles, deactivation.
- **Rentals:** properties, bookings and inspections, Paystack **escrow**
  payments (held until move-in, refunds, landlord rejections, renewals
  quoted and confirmed before charging), tenancy agreements (updated on
  renewal), rent-change notices to a listing's tenants, reviews,
  favourites, eviction requests (reviewed by a super admin).
- **Identity verification:** means of ID for everyone and ownership
  documents for landlords, stored privately and reviewed by moderators.
  Every ID number is also checked with the body that issued it (Prembly),
  which verifies a tenant outright when the name matches; Verified badges;
  Platform Controls (only verified landlords' listings, hold payouts to
  unverified landlords).
- **Money safety:** payouts and refunds are never sent twice (one money
  action per payment at a time, and Paystack is asked first), with an
  admin Payouts & Refunds screen for anything that didn't go through.
- **Marketplace:** vendors (admin-approved), products, orders with held
  payments and auto-release.
- **Chat:** tenant/landlord chats tied to payment, marketplace order chats,
  and customer-support chats with auto-assignment, transfers, internal
  notes, saved replies, ratings and a support dashboard.
- **Reach:** in-app notifications over Socket.IO, Web Push, and emails for
  codes and unread messages.
- **Admin console:** three admin levels, moderation, reports, activity log.

**Full documentation:** `docs/Backend Developer Guide.pdf` (architecture,
data model, every endpoint and job, configuration). The source is
`docs/guides/backend_guide.html`; rebuild with `python3 docs/guides/build.py`.

## Local setup

1. Create a free project at [supabase.com](https://supabase.com). Project
   Settings > Database gives you the pooled and direct connection
   strings; Project Settings > API gives you the URL and service role key.
2. `cp .env.example .env` and fill it in. `.env.example` lists every
   setting with a comment; at minimum `DATABASE_URL`, `DIRECT_URL`,
   `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` and two random secrets
   (`openssl rand -hex 32` twice) for `JWT_ACCESS_SECRET` /
   `JWT_REFRESH_SECRET`.
3. In Supabase Storage, create a **public** bucket named
   `homeservant-uploads` (the `SUPABASE_STORAGE_BUCKET` default). The
   **private** bucket for ID documents (`homeservant-private`, the
   `SUPABASE_PRIVATE_BUCKET` default) is created by the API on startup;
   if you create it yourself, it must NOT be public.
   Leave the public bucket's **Allowed MIME types** empty (it then takes
   every type), or include `image/*` and `video/mp4`, `video/quicktime`,
   `video/x-m4v`, `video/webm` (listing walkthrough videos). The API checks
   this on startup and logs any type the bucket would refuse. Videos are
   capped at 50 MB in the app (the Free plan's per-file limit); if you raise
   the project's upload limit, raise `_maxVideoBytes` in
   `lib/features/landlord/landlord_add_property_screen.dart` to match.
4. `npm install`
5. `npm run prisma:migrate` — creates or upgrades the database schema.
6. `npm run start:dev` — the API is at `http://localhost:3000/api` and
   restarts on file changes.

With `OTP_PROVIDER=console` (the default), verification codes print to
this terminal instead of being emailed.

## Tests

The tests in `test/` run the real services against a real, **disposable**
Postgres (every table is emptied before each test — never point this at a
real database). Only sockets, email and push are faked.

```bash
createdb hs_test
DIRECT_URL=postgresql://localhost/hs_test npx prisma migrate deploy
TEST_DATABASE_URL=postgresql://localhost/hs_test npm test
```

The Prisma CLI reads its connection URL from `prisma.config.ts`
(`DIRECT_URL`, falling back to `DATABASE_URL`); since Prisma 7 it is no
longer in `schema.prisma`. The app itself connects with `DATABASE_URL`
through the `pg` driver adapter (see `src/prisma/prisma.service.ts`).

`npx tsc --noEmit -p tsconfig.json` type-checks. GitHub Actions
(`.github/workflows/ci.yml`) runs the type check, applies the migrations and
checks they match `prisma/schema.prisma`, runs these tests, and runs the
Flutter analyzer and tests, on every pull request.

## Changing the database

Edit `prisma/schema.prisma`, then add a migration folder under
`prisma/migrations/` (`npx prisma migrate dev --name what_changed`, or
hand-write the SQL and verify it with `npx prisma migrate diff
--from-url "$DATABASE_URL" --to-schema-datamodel prisma/schema.prisma`).
Prefer additive changes so the running app keeps working during a deploy.

## Real OTP email via Resend

1. Create a free account at [resend.com](https://resend.com).
2. **Domains > Add Domain**, enter the domain you own, and add the DNS
   records it gives you (SPF/DKIM, usually a couple of `TXT` records and
   sometimes an `MX`) at your domain registrar. Verification is automatic
   once they propagate — can take a few minutes to a few hours.
3. **API Keys > Create API Key** — copy it, this is `RESEND_API_KEY`.
4. Set `RESEND_FROM_EMAIL` to an address at your now-verified domain, e.g.
   `"HomeServant <otp@yourdomain.com>"` — the display name is optional but
   the address must be on the verified domain (Resend rejects sends from
   an unverified one).
5. Set `OTP_PROVIDER="resend"` alongside those two.

Without a verified domain, Resend's free tier only lets you send to the
email address you signed up with — fine for solo testing, not for real
signups.

## Google Sign-In

1. Create a project at [Google Cloud Console](https://console.cloud.google.com).
2. **APIs & Services > OAuth consent screen** — External user type, app
   name/support email, add the `email`/`profile`/`openid` scopes. Testing
   mode is fine until you're ready to publish.
3. **APIs & Services > Credentials > Create Credentials > OAuth client
   ID** — Application type **Web application**. Add every origin that'll
   trigger sign-in (deployed web app URL(s), `http://localhost:<port>`
   for local dev) under **Authorized JavaScript origins**.
4. Set `GOOGLE_CLIENT_ID` to the client ID it gives you (not secret — the
   client secret Google also generates isn't used here at all, since this
   verifies ID tokens rather than doing a server-side code exchange).
5. Separate client IDs are needed for iOS/Android if the mobile app also
   gets Google Sign-In later — not set up yet, web-only for now.

## Deploying to Render

The database and storage live on Supabase; Render only runs the API
container.

1. Push this repo to GitHub/GitLab (Render deploys from a git remote).
2. In the Render dashboard: **New > Blueprint**, point it at this repo.
   `/render.yaml` (repo root — Render's Blueprint discovery doesn't look in
   subdirectories, hence it isn't inside `backend/` alongside everything
   else) provisions the web service, with `rootDir: backend` telling Render
   where the actual Dockerfile/build context lives.
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
   experience for login/OTP, and drops every open chat socket (see
   **Real-time chat** below) — move to a paid instance before real users
   depend on this. (Open chats reconnect on their own when the service
   wakes — the app fetches a fresh sign-in token for every reconnect.)

The Dockerfile runs `prisma migrate deploy` on every boot, so pushing a new
migration and redeploying is enough to apply it — no separate migration
step needed.

## Optional features and their settings

| Setting | What it turns on |
|---|---|
| `PAYSTACK_SECRET_KEY` | Payments, payouts and bank-account checks. |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` | Web Push. Generate the keys once with `npx web-push generate-vapid-keys`; the subject is a `mailto:` address or your site URL. Without them push is off. |
| `APP_URL` | The web app's address for links in emails and where Paystack returns a payer after checkout (falls back to the first `CORS_ORIGINS` entry). |
| `SUPABASE_PRIVATE_BUCKET` | Name of the private bucket for identity documents (default `homeservant-private`; created on startup if missing). |
| `ID_CHECK_PROVIDER` | `prembly` checks every submitted ID number with the body that issued it (needs `PREMBLY_X_API_KEY`; `PREMBLY_APP_ID` only matters on Prembly's retired hosts, and `PREMBLY_BASE_URL` overrides the API host). `console` (default) checks nothing and every submission waits for a moderator. See *ID checks* below. |
| `SUPPORT_AUTO_ASSIGN` | `false` stops auto-assigning new support chats to on-duty admins. |
| `SUPPORT_UNCLAIMED_REMINDER_MINUTES`, `SUPPORT_UNCLAIMED_ESCALATION_MINUTES`, `SUPPORT_REPLY_ESCALATION_MINUTES` | Support reminder and escalation delays (defaults 5, 15, 10). |

## ID checks (Prembly / Identitypass)

Every ID number someone submits — NIN, driver's licence, voter's card,
international passport — is looked up with the body that issued it, and the
name on record is compared against the name on the account.

1. Take the secret key from the Prembly dashboard.
2. Set `PREMBLY_X_API_KEY` and `ID_CHECK_PROVIDER="prembly"`. That's all
   the current API needs — it authenticates on the key alone.

**Before changing the host or the endpoints, read this.** Measured on
2026-09-28 against a real key:

- `https://api.prembly.com/identitypass` is the live host, and the default
  here. Prembly's older `api.myidentitypass.com` and
  `sandbox.myidentitypass.com` hosts **no longer answer**: TLS completes and
  then the connection is dropped with no reply, from curl and from Node's
  fetch alike. Their `dashboard.myidentitypass.com` has an expired
  certificate. Treat any documentation on `developer.myidentitypass.com` as
  describing a retired platform — including its `/api/v2/biometrics/...`
  paths, which 404 on the live host.
- Auth is the `x-api-key` header alone. Sending no key gives
  "Authentication credentials were not provided"; a key Prembly doesn't
  accept gives "Invalid API key or inactive organisation". `app-id` makes no
  difference, so `PREMBLY_APP_ID` is optional and only sent when set.
- There is no sandbox subdomain: `sandbox.prembly.com` does not resolve.
- **The per-type endpoint paths in `ENDPOINTS` are unconfirmed.** Every path
  under `/identitypass/verification/` returns 401 before routing resolves —
  a made-up endpoint name answers identically to a real one — so they cannot
  be probed without a key that authenticates. They follow Prembly's docs,
  whose own pages disagree about host, version and payload key. When a
  working key exists, confirm each path and the name each endpoint returns,
  and correct that one table.
- Payload keys vary per endpoint and country (`firstname`/`surname`,
  `firstName`/`lastName`, `first_name`/`last_name`, a single `fullName`, or
  `identity_name`), so the reader accepts all of them. The current NIN
  response also carries an **empty** `nin_data: {}` next to the real `data`,
  which is why an empty object is never treated as the payload.

What each outcome does (`IdCheckStatus` on `IdentityVerification`):

| Outcome | What it means | What happens |
|---|---|---|
| `MATCH` | The number exists and carries this person's name. | A **tenant** is verified immediately, with no moderator. A landlord still goes to the queue — nothing can vouch for a certificate of ownership except a person reading it. |
| `MISMATCH` | The number exists, under a different name. | Stays pending, with the name on record shown to the reviewer. |
| `NOT_FOUND` | No such number. | Stays pending. |
| `UNSUPPORTED` | No provider configured, or nothing to check against. | Stays pending. |
| `ERROR` | The provider was down, out of credit, or answered with something unusable. | Stays pending; a moderator can press "Check with the issuing body" to try again. |

Two things worth knowing before changing any of this:

- **A check never blocks a submission.** It runs inside signup, so a
  provider being down has to leave someone with a pending submission
  rather than a failed signup. `IdCheckProvider.check` returns `ERROR`
  instead of throwing — see `src/id-check/id-check-provider.interface.ts`.
- **Lookups cost money**, so one is only spent when the number is new or
  the last attempt produced no answer. Resubmitting the same digits after
  a rejection reuses the old outcome; the console's re-check button is the
  way to force a fresh one.

Whether a name matches is decided by `src/id-check/name-match.ts`, which
compares names as unordered sets of parts (Nigerian names are written
surname-first about as often as surname-last) and needs two parts to agree.
It tolerates one typo in a long name and none in a short one. Loosening
that rule hands out verified badges; tightening it only costs a moderator a
glance, so err strict.

## Paystack setup

1. **Keys:** Paystack Dashboard > Settings > API Keys & Webhooks. Put the
   secret key in `PAYSTACK_SECRET_KEY` (test key while testing, live key
   in production). Test and Live mode have separate keys *and* separate
   webhook URLs.
2. **Webhook URL:** on the same page, set the Webhook URL (for the mode
   you're using) to `https://<your-api>/api/paystack/webhook` and save.
   Paystack sends every event there; the API acts on `charge.success`
   (payment confirmed) and `transfer.failed` / `transfer.reversed` (a
   payout that didn't reach the landlord goes back to owed and shows on
   the admin Payouts & Refunds screen). Each request is checked against
   the `x-paystack-signature` header using `PAYSTACK_SECRET_KEY`, so the
   key and the webhook must be from the same mode.
3. **Transfers:** payouts are Paystack Transfers from your Paystack
   balance. Turn off OTP for transfers (Settings > Preferences) or API
   payouts wait for an OTP nobody enters, and keep enough balance (Paystack
   settles card payments into it on its normal schedule).
4. **Check it:** make a test payment in Test mode; the booking should move
   to "paid" within seconds. If it doesn't, Paystack's webhook logs
   (Settings > API Keys & Webhooks) show each delivery and the response.

## Resetting all chats (testing)

`scripts/clear_all_chats.sql` deletes every conversation, message, internal
note, transfer record, chat notification and support-dashboard row, and
nothing else (users, listings, bookings and payments stay). Run it in the
Supabase SQL Editor: preview first (part 1), then delete (part 2, one
transaction). It is permanent, so take a backup first.

## The first admin

Admin accounts can't sign up or use Google sign-in. The very first admin is
created once with:

```bash
curl -X POST https://<your-api>/api/admin/bootstrap \
  -H "x-admin-bootstrap-secret: <ADMIN_BOOTSTRAP_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"…","fullName":"…"}'
```

That route refuses once any admin exists. Every later admin is invited from
the console by a super admin (an emailed code plus a temporary password),
and the console records who invited them. Admins sign in only at the web
app's `/#/admin-login` page — the regular sign-in pages refuse admin
accounts. See `docs/Admin Guide.pdf`, including how to recover if the
console is ever taken over.

## Not built yet

- **SMS codes** — email (Resend) is wired up; SMS isn't. Implement
  `OtpProvider` (`src/otp/otp-provider.interface.ts`) if needed.
- **Biometric / document KYC** — ID *numbers* are checked with the issuing
  body (see *ID checks* above), but nothing compares a selfie against the
  photo on record, and a landlord's ownership documents are still read by a
  moderator rather than machine-checked.
- **Changing an account's email** — deliberately not offered (it would
  need re-verification). Passwords change via `PATCH /api/auth/password`.
- **Scaling beyond one instance** — the Socket.IO gateway and online
  presence are in-process; running several instances would need a Redis
  adapter.
