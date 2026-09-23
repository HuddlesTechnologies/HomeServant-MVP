# Multi-stage build: compile with dev deps, run with only prod deps.
FROM node:20-slim AS build
WORKDIR /app
COPY package*.json ./
COPY prisma ./prisma
RUN npm install
COPY . .
RUN npm run build

FROM node:20-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
COPY prisma ./prisma
RUN npm install --omit=dev && npx prisma generate
COPY --from=build /app/dist ./dist

EXPOSE 3000
# Applies any pending migrations, then starts the API — safe to run on
# every deploy since already-applied migrations are skipped.
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/main.js"]
