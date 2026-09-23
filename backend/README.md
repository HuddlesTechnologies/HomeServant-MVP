# HomeServant API

NestJS + Prisma + PostgreSQL (Supabase) backend for the HomeServant Flutter
app (mobile and web). Covers auth (including Google Sign-In), user
profiles, properties, bookings, favorites, file uploads, reviews, chat,
and the marketplace (vendors, products, orders) — the pieces the current
app screens actually call. See **Not built yet** below for what's
intentionally out of scope for this pass.

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
- `POST /api/auth/google` with `{ idToken, role? }` — verifies the ID
  token the client's Google Sign-In SDK returned, then finds-or-creates
  the matching user (matched by Google's `sub` claim first, falling back
  to email — so an existing email/password account gets linked rather
  than erroring on first Google sign-in). `role` is required only when no
  matching user exists yet. Skips OTP entirely — Google already verified
  the email. See **Google Sign-In** below for the Cloud Console setup.
- `POST /api/auth/refresh` — rotates a refresh token for a new pair; the
  old one is revoked the moment this succeeds, so a leaked-and-replayed
  refresh token stops working as soon as the real client refreshes.
- `POST /api/auth/logout` — revokes one refresh token.
- `PATCH /api/auth/password` (authenticated) with `{ currentPassword,
  newPassword }` — also revokes every other refresh token, so changing
  your password signs other sessions out.

Everything else (`/api/users/me`, `/api/properties`, `/api/bookings`,
`/api/favorites`, `/api/uploads`, `/api/reviews`, `/api/threads`,
`/api/vendors`, `/api/marketplace/*`) expects `Authorization: Bearer
<accessToken>` except `GET /api/properties`, `GET /api/properties/:id`,
`GET /api/reviews`, and `GET /api/marketplace/products*`, which are
public so the browse feeds don't require login.

### File uploads

`POST /api/uploads/sign` with `{ fileName, folder }` (`folder` is
`"properties"`, `"profile-photos"`, `"marketplace-products"`, or
`"vendor-logos"`) returns a one-time `{ path, signedUrl, token,
publicUrl }`. The client `PUT`s the raw file bytes to `signedUrl`
(`Content-Type` matching the file), then saves `publicUrl` wherever it
belongs (property `imageUrl`/`galleryUrls`, a user's `profilePhotoUrl`, a
product's `imageUrls`, a vendor's `logoUrl`) via the relevant update
endpoint — this API never receives the file itself, Supabase Storage
does.

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
- `POST /api/threads` with `{ recipientId, propertyId? }` or `{
  recipientId, orderId? }` — opens a thread, reusing an existing one
  between the same two people about the same property/order instead of
  duplicating it. `orderId` is how marketplace pickup-coordination chats
  (buyer <-> vendor) plug into the same chat system as property chats.
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

### Marketplace

A vendor is a `VENDOR`-role `User` (same signup/login/OTP/Google-auth flow
as everything else) with a 1:1 `VendorProfile` — deliberately *not* a
second, parallel auth system, so vendors get real sessions/password
handling/2FA for free instead of the app's previous "any email/password
logs in, signup form data is discarded" placeholder.

- `POST /api/vendors/me` with `{ businessName, category, state, rcNumber?,
  logoUrl? }` — creates the caller's shop (`VENDOR` role only, one per
  account). `GET/PATCH /api/vendors/me` read/update it; `PATCH` also
  accepts `bankName`/`accountNumber`/`accountName` (payout details — see
  **Not built yet**, payouts themselves aren't automated), and `isActive:
  false` is "Deactivate Shop" — hides every one of the vendor's products
  from the public catalog without deleting anything.
- `GET /api/marketplace/products` (public; `?category=`, `?search=`,
  `?vendorId=`) / `GET /api/marketplace/products/:id` (public) — only
  ever returns `isAvailable` products from `isActive` vendors.
  `GET /api/marketplace/products/mine` (vendor only) includes unavailable
  ones too, so a vendor can see and re-enable something they deleted.
  `POST`/`PATCH /api/marketplace/products/:id` (vendor, own products
  only) create/update a listing; `DELETE` is a soft delete
  (`isAvailable = false`) rather than a real row delete, since a hard
  delete would orphan any past order that references it.
- `POST /api/marketplace/orders` with `{ items: [{ productId, quantity,
  fulfillment }], paymentMethod }` — buyer info (`customerName/Phone/
  Address`) comes from the authenticated account's own profile, not a
  separate checkout form. Stock is checked and decremented atomically per
  item inside a transaction (a conditional update guarded by `stock >=
  quantity`, not a plain read-then-write), so two concurrent buyers can't
  both oversell the last unit. `GET /api/marketplace/orders/mine` is the
  buyer's own order history (scoped by buyer id — every buyer used to see
  every order ever placed, by everyone, before this existed).
  `GET /api/marketplace/orders/vendor` (vendor only) is the flattened
  order-item view for that vendor's own sales.
  `PATCH /api/marketplace/orders/items/:itemId/status` (vendor, own items
  only) with `{ status: "COMPLETED" | "CANCELLED" }`, and `PATCH
  .../items/:itemId/read` mark a notification seen.
- **No payment gateway is wired up** — an order is recorded with whatever
  `paymentMethod` label the client sends; nothing actually charges the
  buyer. See **Not built yet**.

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

- **Tenancy agreement storage** — PDF generation is client-side only
  (`lib/features/dashboard/legal/tenancy_agreement_pdf.dart`); nothing
  persists the generated document server-side yet.
- **Payments** — no Paystack/Flutterwave integration for rent or
  marketplace checkout; a marketplace order is recorded with whatever
  `paymentMethod` label the client sends, nothing actually charges
  anyone. Needs a real merchant account and API keys.
- **Marketplace vendor payouts** — `VendorProfile.bankName/accountNumber/
  accountName` are stored but nothing automates paying a vendor out;
  that's tied to the payments gap above.
- **Vendor application review** — every vendor is active immediately on
  signup; there's no pending/approved/rejected moderation workflow (the
  old mocked signup's "we'll review your application" message implied
  one, but nothing modelled it either).
- **SMS OTP delivery** — email (`OTP_PROVIDER=resend`, see below) is
  wired up; SMS via Termii (for Nigerian phone numbers) isn't. Implement
  `OtpProvider` (see `src/otp/otp-provider.interface.ts`) for it if a
  phone-based flow is ever needed.
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
