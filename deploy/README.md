# Production Deploy

## 1. Prepare secrets
1. Copy `.env.production.example` to `.env.production`.
2. Replace every `change_me` value.
3. Put the real APNS auth key into `APNS_PRIVATE_KEY` with escaped newlines.
4. Set `ALLOW_DEV_APPLE_SUB_TOKENS=false`.

## 2. Build and run
```bash
cd deploy
cp .env.production.example .env.production
docker compose -f docker-compose.prod.yml up -d --build
```

## 3. Readiness checks
```bash
curl http://127.0.0.1:8000/health/live
curl http://127.0.0.1:8000/health/ready
docker compose -f docker-compose.prod.yml ps
```

## 4. Before public traffic
- Put the API behind HTTPS and a real domain.
- Move media from local disk to object storage/CDN when load grows.
- Configure Postgres backups.
- Configure central logs and error monitoring.
- Smoke-test push notifications with a production-signed iPhone build.
