# AI Automation Platform — Production Deployment (n8n on Kubernetes)

A secure, scalable, highly-available deployment architecture for an n8n-based
AI Automation Platform, built with Docker, Kubernetes, Traefik, Let's Encrypt
TLS, GitHub Actions CI/CD, Prometheus/Grafana monitoring, and automated backups.

---

## 1. Architecture Summary

```
Internet
   │
   ▼
[ Cloudflare DNS + Proxy ]
   │  (HTTPS 443)
   ▼
[ Traefik Ingress Controller ]  ── cert-manager (Let's Encrypt, auto TLS renewal)
   │
   ▼
[ Kubernetes Cluster (3 nodes, multi-AZ) ]
   ├── Namespace: n8n-prod
   │     ├── Deployment: n8n (2-6 replicas, HPA on CPU/mem)
   │     ├── Service: n8n-svc (ClusterIP)
   │     ├── StatefulSet: postgres (primary DB, PVC-backed)
   │     ├── StatefulSet: redis (queue mode / Bull MQ for n8n workers)
   │     ├── ConfigMap + Secret (env vars, credentials, encryption key)
   │     ├── HPA (Horizontal Pod Autoscaler)
   │     ├── NetworkPolicy (deny-all default, allow only required paths)
   │     └── PodDisruptionBudget
   ├── Namespace: monitoring
   │     ├── Prometheus + Alertmanager
   │     ├── Grafana (dashboards)
   │     └── Loki + Promtail (log aggregation)
   └── Namespace: backup
         └── CronJob: pg_dump + restic → S3/Object storage
```

See `docs/ARCHITECTURE.md` for the full diagram description and design
rationale, and `docs/DEPLOYMENT_GUIDE.md` for the exact step-by-step build.

---

## 2. Repository Layout

```
n8n-platform/
├── README.md                      ← you are here
├── docker/
│   ├── Dockerfile                 ← custom n8n image (hardened)
│   └── docker-compose.yml         ← local dev / staging stack
├── k8s/
│   ├── 00-namespace.yaml
│   ├── 01-secrets.yaml
│   ├── 02-configmap.yaml
│   ├── 03-postgres-statefulset.yaml
│   ├── 04-redis-statefulset.yaml
│   ├── 05-n8n-deployment.yaml
│   ├── 06-n8n-service.yaml
│   ├── 07-hpa.yaml
│   ├── 08-ingress-traefik.yaml
│   ├── 09-networkpolicy.yaml
│   ├── 10-pdb.yaml
│   └── 11-cert-manager-issuer.yaml
├── ci-cd/
│   └── .github/workflows/deploy.yml
├── monitoring/
│   ├── prometheus-values.yaml
│   ├── grafana-dashboard-n8n.json
│   └── loki-values.yaml
├── backup/
│   ├── backup-cronjob.yaml
│   └── backup.sh
└── docs/
    ├── ARCHITECTURE.md
    ├── DEPLOYMENT_GUIDE.md
    └── DEMO_SCRIPT.md
```

---

## 3. Quick Start (Local)

```bash
git clone https://github.com/<you>/n8n-platform.git
cd n8n-platform/docker
cp .env.example .env        # fill in POSTGRES_PASSWORD, N8N_ENCRYPTION_KEY, etc.
docker compose up -d
# n8n available at http://localhost:5678
```

## 4. Quick Start (Production — Kubernetes)

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-secrets.yaml
kubectl apply -f k8s/02-configmap.yaml
kubectl apply -f k8s/03-postgres-statefulset.yaml
kubectl apply -f k8s/04-redis-statefulset.yaml
kubectl apply -f k8s/05-n8n-deployment.yaml
kubectl apply -f k8s/06-n8n-service.yaml
kubectl apply -f k8s/07-hpa.yaml
kubectl apply -f k8s/11-cert-manager-issuer.yaml
kubectl apply -f k8s/08-ingress-traefik.yaml
kubectl apply -f k8s/09-networkpolicy.yaml
kubectl apply -f k8s/10-pdb.yaml
kubectl get pods -n n8n-prod -w
```

Full explanation of every command and file: `docs/DEPLOYMENT_GUIDE.md`.

## 5. CI/CD

Push to `main` → GitHub Actions builds the Docker image, scans it (Trivy),
pushes to GHCR, then runs `kubectl apply` / `helm upgrade` against the
cluster via a stored kubeconfig secret. See `ci-cd/.github/workflows/deploy.yml`.

## 6. Monitoring & Logging

Prometheus scrapes n8n `/metrics`, node-exporter, and kube-state-metrics.
Grafana visualizes workflow execution rate, error rate, queue depth, pod
CPU/memory. Loki + Promtail centralize container logs. See `monitoring/`.

## 7. Backup & Recovery

Nightly CronJob dumps Postgres (`pg_dump`) and n8n encryption key, packages
with `restic`, and pushes to S3-compatible object storage with 30-day
retention. Recovery steps in `docs/DEPLOYMENT_GUIDE.md` §8.

## 8. Security Highlights

- TLS everywhere (Traefik + cert-manager, auto-renewed Let's Encrypt certs)
- Secrets stored in Kubernetes Secrets (sealed/external-secrets recommended for real prod)
- Non-root container user, read-only root filesystem where possible
- NetworkPolicy: default-deny, explicit allow rules only
- RBAC least-privilege ServiceAccounts
- Image scanning in CI (Trivy) before push
- Rate limiting + IP allowlist at Traefik middleware layer

## 9. Demo Video

5–10 min walkthrough script in `docs/DEMO_SCRIPT.md` — covers architecture,
live deployment, a triggered CI/CD pipeline run, a workflow execution in
n8n, and a live Grafana dashboard.
