# Production Deployment Guide

This guide covers deploying happy-server in production with external PostgreSQL and Redis.

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- A `HANDY_MASTER_SECRET` environment variable set (generate with `openssl rand -hex 32`)

### Step 1: Prepare Environment

```bash
# Set your master secret (generate a secure random string)
export HANDY_MASTER_SECRET=$(openssl rand -hex 32)

# Or save it to .env file
echo "HANDY_MASTER_SECRET=$(openssl rand -hex 32)" > .env
```

### Step 2: Deploy with Docker Compose

```bash
# Use the production compose file
docker-compose -f docker-compose.production.yml up -d

# Wait for PostgreSQL to be ready (10-15 seconds)
sleep 15

# Run database migrations
docker-compose -f docker-compose.production.yml exec happy-server \
  sh -c "cd packages/happy-server && npx prisma migrate deploy"

# Restart happy-server to ensure clean state
docker-compose -f docker-compose.production.yml restart happy-server

# View logs
docker-compose -f docker-compose.production.yml logs -f happy-server
```

### Step 3: Verify Deployment

```bash
# Check that services are running
docker-compose -f docker-compose.production.yml ps

# Test the API
curl http://localhost:3005/health
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Yes | - | PostgreSQL connection string |
| `REDIS_URL` | Yes | - | Redis connection string |
| `HANDY_MASTER_SECRET` | Yes | - | Master secret for auth/encryption |
| `NODE_ENV` | No | `production` | Node environment |
| `PORT` | No | `3005` | Server port |
| `PGLITE_DIR` | No | - | **Must be unset** for external DB |

### Database Modes

happy-server supports two database modes:

1. **Standalone Mode** (default in Dockerfile)
   - Uses embedded PGlite database
   - Suitable for single-server, low-traffic deployments
   - No external database required

2. **Production Mode** (recommended)
   - Uses external PostgreSQL
   - Scalable and production-ready
   - Requires `DATABASE_URL` and `PGLITE_DIR` to be unset

**Important**: The default Docker image has `PGLITE_DIR=/data/pglite` set. To use external PostgreSQL, you must explicitly override this in your deployment configuration.

### PostgreSQL 18+ Volume Requirements

PostgreSQL 18 changed its data directory structure. You must mount `/var/lib/postgresql` (not `/var/lib/postgresql/data`):

```yaml
postgres:
  image: postgres:18
  volumes:
    - postgres_data:/var/lib/postgresql  # Correct for PG 18+
```

If upgrading from an older PostgreSQL version with existing data, see the [PostgreSQL upgrade guide](https://github.com/docker-library/postgres/issues/37).

## Production Checklist

### Security

- [ ] Generate a strong `HANDY_MASTER_SECRET` (32+ random bytes)
- [ ] Use strong PostgreSQL passwords
- [ ] Configure firewall rules to restrict database access
- [ ] Enable SSL/TLS for database connections in production
- [ ] Set up proper network segmentation (databases not exposed publicly)

### Monitoring

- [ ] Set up health check endpoints monitoring
- [ ] Configure log aggregation
- [ ] Set up PostgreSQL monitoring (connections, queries, disk usage)
- [ ] Monitor Redis memory usage

### Backup

- [ ] Configure PostgreSQL automatic backups
- [ ] Test backup restoration procedure
- [ ] Set up Redis persistence if needed

### Scaling

- [ ] Use connection pooling for PostgreSQL (e.g., PgBouncer)
- [ ] Consider Redis clustering for high availability
- [ ] Set up load balancer for multiple happy-server instances

## Troubleshooting

### Server still using PGlite despite DATABASE_URL being set

**Symptom**: Logs show "Migrating database in /data/pglite..." even with `DATABASE_URL` configured.

**Cause**: The Docker image has `PGLITE_DIR=/data/pglite` set by default.

**Solution**: Explicitly unset `PGLITE_DIR` in your docker-compose command:

```yaml
services:
  happy-server:
    command:
      - sh
      - -c
      - |
        export PGLITE_DIR=""
        exec node_modules/.bin/tsx --tsconfig packages/happy-server/tsconfig.json packages/happy-server/sources/main.ts
```

### PostgreSQL connection refused (P1001)

**Symptom**: `Error: P1001: Can't reach database server at postgres:5432`

**Causes**:
1. PostgreSQL container not started
2. PostgreSQL still initializing
3. Network connectivity issues

**Solutions**:
```bash
# Check PostgreSQL is running
docker-compose ps postgres

# Check PostgreSQL logs
docker-compose logs postgres

# Verify PostgreSQL is ready
docker-compose exec postgres pg_isready -U postgres

# Test connection from happy-server container
docker-compose exec happy-server sh -c 'apt-get update && apt-get install -y postgresql-client && psql $DATABASE_URL -c "SELECT 1"'
```

### PostgreSQL 18 won't start with existing data

**Symptom**: PostgreSQL logs show error about incompatible data format.

**Cause**: Upgrading from older PostgreSQL version with old volume mount path.

**Solution**: Either use a fresh volume or follow the upgrade guide:
```bash
# Option 1: Start fresh (loses data)
docker-compose down -v
docker volume rm happy_postgres_data
docker-compose up -d

# Option 2: Follow PostgreSQL upgrade guide
# https://github.com/docker-library/postgres/issues/37
```

### Migrations fail to apply

**Solution**: Ensure PostgreSQL is fully initialized before running migrations:
```bash
# Wait for PostgreSQL
for i in {1..30}; do
  docker-compose exec postgres pg_isready -U postgres && break
  sleep 2
done

# Then run migrations
docker-compose exec happy-server sh -c "cd packages/happy-server && npx prisma migrate deploy"
```

## Manual Migration Script

For automated deployments, use this migration script:

```bash
#!/bin/bash
set -e

cd ~/happy

echo "Starting services..."
docker-compose -f docker-compose.production.yml up -d postgres redis

echo "Waiting for PostgreSQL..."
for i in {1..60}; do
  if docker-compose -f docker-compose.production.yml exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
    echo "PostgreSQL is ready!"
    break
  fi
  [ $i -eq 60 ] && { echo "PostgreSQL timeout"; exit 1; }
  sleep 1
done

sleep 3

echo "Starting happy-server..."
docker-compose -f docker-compose.production.yml up -d happy-server

sleep 5

echo "Running migrations..."
docker-compose -f docker-compose.production.yml exec -T happy-server \
  sh -c "cd packages/happy-server && npx prisma migrate deploy"

echo "Restarting happy-server..."
docker-compose -f docker-compose.production.yml restart happy-server

echo "Deployment complete!"
docker-compose -f docker-compose.production.yml logs --tail=50 -f happy-server
```

## Advanced: Custom Docker Image

To build a custom image without PGlite dependencies:

```bash
# Build using Dockerfile.production
docker build -t your-registry/happy-server:latest -f Dockerfile.production .

# Push to your registry
docker push your-registry/happy-server:latest

# Update docker-compose.production.yml to use your image
```

Or use the provided build script:

```bash
./build-production.sh latest
```

## Further Reading

- [Main Deployment Documentation](docs/deployment.md)
- [Docker Compose Production Config](docker-compose.production.yml)
- [Database Client Implementation](packages/happy-server/sources/storage/db.ts)
- [Standalone Mode](packages/happy-server/sources/standalone.ts)