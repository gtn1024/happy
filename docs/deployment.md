# Deployment

This document describes how to deploy the Happy backend (`packages/happy-server`) and the infrastructure it expects.

## Deployment Options

Happy Server supports two deployment modes:

1. **Standalone mode** (default): Uses embedded PGlite database and local file storage. Suitable for single-server deployments.
2. **Production mode**: Uses external PostgreSQL, Redis, and S3-compatible storage. Suitable for scalable, multi-instance deployments.

## Runtime overview
- **App server:** Node.js running `tsx ./sources/main.ts` (Fastify + Socket.IO).
- **Database:** Postgres via Prisma.
- **Cache:** Redis (currently used for connectivity and future expansion).
- **Object storage:** S3-compatible storage for user-uploaded assets (MinIO works).
- **Metrics:** Optional Prometheus `/metrics` server on a separate port.

## Required services
1. **Postgres**
   - Required for all persisted data.
   - Configure via `DATABASE_URL`.

2. **Redis**
   - Required by startup (`redis.ping()` is called).
   - Configure via `REDIS_URL`.

3. **S3-compatible storage**
   - Used for avatars and other uploaded assets.
   - Configure via `S3_HOST`, `S3_PORT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET`, `S3_PUBLIC_URL`, `S3_USE_SSL`.

## Environment variables
**Required**
- `DATABASE_URL`: Postgres connection string.
- `HANDY_MASTER_SECRET`: master key for auth tokens and server-side encryption.
- `REDIS_URL`: Redis connection string.
- `S3_HOST`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET`, `S3_PUBLIC_URL`: object storage config.

**Common**
- `PORT`: API server port (default `3005`).
- `METRICS_ENABLED`: set to `false` to disable metrics server.
- `METRICS_PORT`: metrics server port (default `9090`).
- `S3_PORT`: optional S3 port.
- `S3_USE_SSL`: `true`/`false` (default `true`).

**Optional integrations**
- GitHub OAuth/App: `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `GITHUB_APP_ID`, `GITHUB_PRIVATE_KEY`, `GITHUB_WEBHOOK_SECRET`, plus redirect URL/URI.
  - `GITHUB_REDIRECT_URL` is used by the OAuth callback handler.
  - `GITHUB_REDIRECT_URI` is used by the GitHub App initializer.
- Voice: `ELEVENLABS_API_KEY` (required for `/v1/voice/token` in production).
- Debug logging: `DANGEROUSLY_LOG_TO_SERVER_FOR_AI_AUTO_DEBUGGING` (enables file logging + dev log endpoint).

## Docker image
A production Dockerfile is provided at `Dockerfile.server`.

Key notes:
- The server defaults to port `3005` (set `PORT` explicitly in container environments).
- The image includes FFmpeg and Python for media processing.

## Kubernetes manifests
Example manifests live in `packages/happy-server/deploy`:
- `handy.yaml`: Deployment + Service + ExternalSecrets for the server.
- `happy-redis.yaml`: Redis StatefulSet + Service + ConfigMap.

The deployment config expects:
- Prometheus scraping annotations on port `9090`.
- A secret named `handy-secrets` populated by ExternalSecrets.
- A service mapping port `3000` to container port `3005`.

## Local dev helpers
The server package includes scripts for local infrastructure:
- `yarn workspace happy-server db` (Postgres in Docker)
- `yarn workspace happy-server redis`
- `yarn workspace happy-server s3` + `s3:init`

Use `.env`/`.env.dev` to load local settings when running `yarn workspace happy-server dev`.

## Production Deployment with External Databases

### Using Docker Compose

A production-ready `docker-compose.production.yml` is provided that uses external PostgreSQL and Redis:

```yaml
version: '3.8'
services:
  happy-server:
    image: your-registry/happy-server:latest
    ports:
      - "3005:3005"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://user:pass@postgres:5432/happy-server
      - REDIS_URL=redis://redis:6379
      - HANDY_MASTER_SECRET=${HANDY_MASTER_SECRET}
      - PORT=3005
      - PGLITE_DIR=  # Important: unset to use external DB
    command:
      - sh
      - -c
      - |
        export PGLITE_DIR=""
        exec node_modules/.bin/tsx --tsconfig packages/happy-server/tsconfig.json packages/happy-server/sources/main.ts
    depends_on:
      - postgres
      - redis
```

### Database Priority

The server prioritizes database connections as follows:

1. If `DATABASE_URL` is set → uses external PostgreSQL via standard Prisma client
2. If `PGLITE_DIR` is set → uses embedded PGlite database
3. Otherwise → defaults to standard Prisma client (requires `DATABASE_URL`)

**Important**: The Docker image sets `PGLITE_DIR=/data/pglite` by default. When using external PostgreSQL, you must explicitly unset this variable in your docker-compose command or use an entrypoint script.

### Database Migrations

For external PostgreSQL:
```bash
# Run migrations manually
docker-compose exec happy-server sh -c "cd packages/happy-server && npx prisma migrate deploy"
```

For PGlite (standalone mode):
```bash
# Migrations are applied automatically via standalone.ts migrate command
docker-compose exec happy-server node_modules/.bin/tsx packages/happy-server/sources/standalone.ts migrate
```

### PostgreSQL 18+ Volume Configuration

PostgreSQL 18 changed its data directory structure. Mount `/var/lib/postgresql` instead of `/var/lib/postgresql/data`:

```yaml
postgres:
  image: postgres:18
  volumes:
    - postgres_data:/var/lib/postgresql  # Not /var/lib/postgresql/data
```

## Implementation references
- Entrypoint: `packages/happy-server/sources/main.ts`
- Standalone mode: `packages/happy-server/sources/standalone.ts`
- Database client: `packages/happy-server/sources/storage/db.ts`
- Dockerfile: `Dockerfile` (standalone), `Dockerfile.production` (external services)
- Production compose: `docker-compose.production.yml`
- Kubernetes manifests: `packages/happy-server/deploy`
- Env usage: `packages/happy-server/sources` (`rg -n "process.env"`)
