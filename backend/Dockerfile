# Multi-stage build: compile with dev deps, run with only prod deps.
#
# node:20-slim is Debian without OpenSSL installed — Prisma's native query
#/schema engine binaries need it (libssl) to run at all, so both stages
# install it before anything that touches Prisma (postinstall's `prisma
# generate`, and later `prisma migrate deploy`) runs.
FROM node:20-slim AS build
WORKDIR /app
RUN apt-get update -y && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*
COPY package*.json ./
COPY prisma ./prisma
RUN npm install
COPY . .
RUN npm run build

FROM node:20-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN apt-get update -y && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*
COPY package*.json ./
COPY prisma ./prisma
RUN npm install --omit=dev && npx prisma generate
COPY --from=build /app/dist ./dist

EXPOSE 3000
# Applies any pending migrations, then starts the API — safe to run on
# every deploy since already-applied migrations are skipped.
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/main.js"]
