# HomeServant API

NestJS 10 + Prisma 5 + PostgreSQL (Supabase) backend for the HomeServant
Flutter app (web and mobile), deployed on Render. It covers:

- **Accounts:** email + password with email codes and optional two-factor,
  Google sign-in (never for admins), profiles, deactivation.
- **Rentals:** properties, bookings and inspections, Paystack **escrow**
  payments (held until move-in, refunds, landlord rejections, renewals
  quoted and confirmed before charging), tenancy agreements (updated on
  renewal), rent-change notices to a listing's tenants, reviews,
  favourites, eviction requests (reviewed by a super admin).
- **Identity verification:** means of ID for everyone and ownership
  documents for landlords, stored privately and reviewed by moderators;
  Verified badges; Platform Controls (only verified landlords' listings,
  hold payouts to unverified landlords).
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
DATABASE_URL=postgresql://localhost/hs_test npx prisma migrate deploy
TEST_DATABASE_URL=postgresql://localhost/hs_test npm test
```

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
| `SUPPORT_AUTO_ASSIGN` | `false` stops auto-assigning new support chats to on-duty admins. |
| `SUPPORT_UNCLAIMED_REMINDER_MINUTES`, `SUPPORT_UNCLAIMED_ESCALATION_MINUTES`, `SUPPORT_REPLY_ESCALATION_MINUTES` | Support reminder and escalation delays (defaults 5, 15, 10). |

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
- **KYC / identity verification** — the signup ID and ownership-document
  steps are UI-only; nothing verifies them server-side yet.
- **Changing an account's email** — deliberately not offered (it would
  need re-verification). Passwords change via `PATCH /api/auth/password`.
- **Scaling beyond one instance** — the Socket.IO gateway and online
  presence are in-process; running several instances would need a Redis
  adapter.
