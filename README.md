# HomeServant

A home-rental and home-services platform for Nigeria:

- **Tenants** find and pay for homes and shortlets.
- **Landlords** list and manage properties and tenants, get paid through
  escrow, chat with paying tenants, and can request evictions.
- **Vendors** sell home-services products in the marketplace.
- **Admins** run support, moderation, ID verification, platform-wide
  controls and payout/refund fixes from a web console.

Everyone gives ID at signup (stored privately and reviewed by admins);
verified landlords and tenants get a Verified badge.

| Part | Tech | Hosted on |
|---|---|---|
| App (`lib/`) | Flutter (web + mobile), go_router, provider, dio, Socket.IO | Vercel (web) |
| API (`backend/`) | NestJS 10, Prisma 5, PostgreSQL, Socket.IO | Render (Docker); database and storage on Supabase |

## Documentation

| Document | For |
|---|---|
| [`docs/App Overview.pdf`](docs/App%20Overview.pdf) | What the app does, for each type of user |
| [`docs/Admin Guide.pdf`](docs/Admin%20Guide.pdf) | Running the admin console: levels, support chats, emergencies |
| [`docs/Frontend Developer Guide.pdf`](docs/Frontend%20Developer%20Guide.pdf) | How the Flutter app is built |
| [`docs/Backend Developer Guide.pdf`](docs/Backend%20Developer%20Guide.pdf) | How the API is built: data, endpoints, jobs, settings |
| [`backend/README.md`](backend/README.md) | Setting up, testing and deploying the API |
| [`CLAUDE.md`](CLAUDE.md) | House rules for code changes (text colour/contrast) |

The PDFs are built from `docs/guides/*.html`: edit the HTML, then run
`python3 docs/guides/build.py` and commit both.

## Running it locally

```bash
# API (see backend/README.md for the .env it needs)
cd backend && npm install && npm run prisma:migrate && npm run start:dev

# App, pointed at the local API
flutter pub get
flutter run -d chrome --web-port 8765 --dart-define=API_BASE_URL=http://localhost:3000/api
```

## Checks

```bash
flutter analyze && flutter test                  # app
cd backend && npx tsc --noEmit -p tsconfig.json  # API type check
TEST_DATABASE_URL=postgresql://localhost/hs_test npm test   # API tests (disposable DB)
```

GitHub Actions runs all of these on every pull request
(`.github/workflows/ci.yml`).

## Deploying

- **API:** Render deploys the backend from `main`. New database migrations
  apply automatically on start. Deploy the API before, or together with,
  an app release that depends on it.
- **Web app:** Vercel builds it from `main` (see `vercel.json`, including
  the Content-Security-Policy).
