// Prisma CLI settings (migrate, generate, studio). Since Prisma 7 the
// connection URL lives here instead of in schema.prisma.
//
// Migrations use DIRECT_URL: Supabase's pooled connection (DATABASE_URL,
// pgbouncer on port 6543) can't run the prepared statements/advisory locks
// `prisma migrate` needs. The app itself connects with DATABASE_URL — see
// PrismaService. Read from process.env without failing when unset, so
// `prisma generate` still works in a Docker build with no database.
import 'dotenv/config';
import { defineConfig } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: { path: 'prisma/migrations' },
  datasource: { url: process.env.DIRECT_URL ?? process.env.DATABASE_URL },
});
