FROM node:20-alpine AS base
WORKDIR /app

FROM base AS deps
COPY package.json package-lock.json* ./
RUN npm install

FROM deps AS build
COPY . .
RUN npm run build

FROM base AS production
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
# Admin scripts run with `docker compose run --rm billing-backend node scripts/...` (e.g. set-master-admin.js).
COPY scripts ./scripts
EXPOSE 3000
CMD ["node", "dist/main.js"]
