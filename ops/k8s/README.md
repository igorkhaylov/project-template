# Kubernetes: the contract and the mapping

No manifests live here yet, on purpose: a chart written before there is a cluster rots.
What this directory holds is the **contract the images already satisfy** and the
**service-by-service mapping** from `ops/compose/docker-compose.yml`, so that writing the
manifests (Kustomize or Helm) is a transcription, not a design exercise.

## The contract (what every image guarantees)

| Requirement | How the template satisfies it | Where |
|---|---|---|
| Environment-agnostic image | all config via env vars (backend) or `/config.js` rendered from `APP_*` at start (frontend); build args carry only version | `backend/config/settings/`, `frontend/nginx/default.conf.template` |
| Stateless containers | static+media in S3, Celery schedule in the DB, no local writes except `/tmp` | `STORAGES`, `django-celery-beat` |
| Liveness ≠ readiness | `/healthz/` (process alive, no deps) and `/readyz/` (db + cache, 503 when degraded); frontend `/healthz` | `backend/apps/common/middleware.py` |
| Probes work with pod-IP `Host` headers | probes are answered before `ALLOWED_HOSTS` validation and before the HTTPS redirect | same middleware, first in `MIDDLEWARE` |
| Separate release step | `scripts/release.sh` = migrate + collectstatic + first superuser; `scripts/entrypoint.sh` = gunicorn only | `backend/scripts/` |
| Non-root | backend uid 1000; frontend `nginx-unprivileged` uid 101 on port 8080 | Dockerfiles |
| Graceful shutdown | gunicorn `--graceful-timeout`, Celery acks on SIGTERM; set `terminationGracePeriodSeconds` ≥ those | `entrypoint.sh`, worker command |
| Scale by replicas | `GUNICORN_WORKERS=2` default; more pods, not more processes | `.env.example` |
| Single scheduler | `celery-beat` must run with exactly one replica | compose comments |
| Starts before dependencies | Django connects lazily, Celery retries the broker (`broker_connection_retry_on_startup`); readiness gates traffic | `config/celery.py` |
| Logs | one JSON object per line on stdout (stage/prod) | `settings/third_party.py` |
| Single-string credentials | `DATABASE_URL`, `REDIS_URL` override the Compose-style `POSTGRES_*`/`REDIS_HOST` | `settings/base.py` |
| Build identity | `APP_VERSION` / `VITE_APP_VERSION` = `sha-<sha>` or `vX.Y.Z`, visible at `/api/v1/meta/` | CI workflows |

## Compose → Kubernetes mapping

| Compose service | Kubernetes | Replicas | Probes | Notes |
|---|---|---|---|---|
| `release` | `Job` (Helm: `pre-install,pre-upgrade` hook) | 1, `backoffLimit: 0` | — | same image as backend, `command: ["bash","scripts/release.sh"]`; the rollout waits for it |
| `backend` | `Deployment` + `Service` (port 8000) | 2+ (HPA on CPU) | liveness `GET /healthz/`, readiness `GET /readyz/` | `PodDisruptionBudget minAvailable: 1` |
| `celery` | `Deployment` | 1+ | liveness: `celery -A config inspect ping -d celery@$HOSTNAME` (exec, generous period) | `terminationGracePeriodSeconds` ≥ longest task you accept to lose |
| `celery-beat` | `Deployment` | **exactly 1**, `strategy: Recreate` | none (or exec `ps`); schedule is in the DB | never `RollingUpdate` (two beats overlap) |
| `frontend` | `Deployment` + `Service` (port 8080) | 2 | liveness+readiness `GET /healthz` | `securityContext.runAsNonRoot: true` works out of the box |
| `nginx` (edge) | **`Ingress`** | — | — | two rules, see below; no container |
| `db` | managed Postgres / operator (CloudNativePG, Zalando) | — | — | not part of the app chart |
| `redis` | managed Redis / operator / a small `StatefulSet` for non-critical use | — | — | `maxmemory-policy noeviction` (broker!) |
| MinIO (host) | external S3-compatible storage | — | — | bucket + credentials provisioned out of band |
| `db-backup` (profile) | `CronJob` | — | — | or the managed service's backups |

### Ingress: the two rules

The edge routes by prefix exactly as `ops/nginx/nginx.conf` does. With the NGINX
Ingress controller the backend-owned prefixes are one regex path:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: 500m
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /((en|ru)/)?(api|admin|rosetta|healthz|readyz)(/|$)
            pathType: ImplementationSpecific
            backend: { service: { name: backend, port: { number: 8000 } } }
          - path: /
            pathType: Prefix
            backend: { service: { name: frontend, port: { number: 8080 } } }
```

Keep the prefix list identical to `backend/config/urls.py`, `ops/nginx/*.conf` and
`frontend/vite.config.ts`. The Ingress controller sets `X-Forwarded-Proto`; nothing in
the app re-sets it.

### Probes (backend Deployment)

```yaml
livenessProbe:
  httpGet: { path: /healthz/, port: 8000 }
  periodSeconds: 10
  failureThreshold: 3
readinessProbe:
  httpGet: { path: /readyz/, port: 8000 }
  periodSeconds: 5
  failureThreshold: 3
startupProbe:
  httpGet: { path: /healthz/, port: 8000 }
  failureThreshold: 30
  periodSeconds: 2
```

No `httpHeaders: Host:` workaround is needed: the middleware answers before
`ALLOWED_HOSTS` is consulted, so `ALLOWED_HOSTS` keeps only the public host names.

### Configuration: ConfigMap vs Secret

Split `.env.example` mechanically:

| ConfigMap (non-secret) | Secret |
|---|---|
| `ENVIRONMENT=prod`, `DJANGO_APP_NAME`, `DJANGO_ALLOWED_HOSTS`, `DJANGO_CSRF_TRUSTED_ORIGINS`, `DJANGO_CORS_ALLOWED_ORIGINS`, `DJANGO_LOG_LEVEL`, `GUNICORN_*`, `DJANGO_MINIO_ENDPOINT`, `DJANGO_MINIO_CUSTOM_URL`, `DJANGO_MINIO_BUCKET_NAME`, `APP_ENVIRONMENT`, `APP_API_BASE_URL` (frontend) | `DJANGO_SECRET_KEY`, `DATABASE_URL`, `REDIS_URL`, `DJANGO_MINIO_ACCESS_KEY`, `DJANGO_MINIO_SECRET_KEY`, `DJANGO_SUPERUSER_PASSWORD` |

`DATABASE_URL` and `REDIS_URL` replace the whole `POSTGRES_*` / `REDIS_HOST` set; the
latter exist only for Compose, where they also provision the containers.

### Resources

The `deploy.resources.limits` in the compose files are a starting point for
`resources.requests/limits`; measure before copying.

## Rollout sequence

1. CI pushes `…/backend:sha-X` and/or `…/frontend:sha-Y` (already the case).
2. Run the `release` Job with `backend:sha-X` → wait for success (Helm hook does this).
3. Roll the `backend`, `celery`, `celery-beat` Deployments to `sha-X`.
4. Roll `frontend` to `sha-Y` independently; the Ingress does not change.
5. Rollback = previous tags; migrations are forward-only, so write them backward-compatible.

## When the cluster exists

1. `ops/k8s/base/` as a Kustomize base (one file per object above) + `overlays/{dev,prod}`
   for hosts, replicas, resources and the image tags. Or a Helm chart with the same
   objects; the Job becomes a hook.
2. Smoke-test locally with `kind`: load the two images, apply, port-forward, hit
   `/readyz/`, `/api/v1/meta/` and `/`.
3. Point `deploy.yml` at the cluster (`kubectl set image` / `helm upgrade --set
   image.tag=sha-…`) instead of SSH. The CI build jobs do not change.
4. Observability: the JSON logs ship as-is; add `/metrics` (django-prometheus) when a
   Prometheus exists.
