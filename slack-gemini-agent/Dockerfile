# -----------------------------------------------------------------------------
# Stage 1: Build & Compile TypeScript
# -----------------------------------------------------------------------------
FROM node:22-alpine AS builder

WORKDIR /app

COPY package*.json tsconfig.json ./
RUN npm ci

COPY src/ ./src/
RUN npm run build

# -----------------------------------------------------------------------------
# Stage 2: Minimal Production Runtime for Google Cloud Run
# -----------------------------------------------------------------------------
FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=builder /app/dist ./dist

# Run as non-root user for security
USER node

EXPOSE 8080

CMD ["node", "dist/index.js"]
