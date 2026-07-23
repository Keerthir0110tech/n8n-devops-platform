# Deployment Guide — Step by Step (Fresher-Friendly)

This guide assumes zero prior Kubernetes experience. Follow it top to
bottom, in order. Every command is explained before you run it.

---

## Phase 0 — Prerequisites

Install on your machine:
- Docker Desktop (or Docker Engine on Linux)
- `kubectl` (Kubernetes CLI)
- A Kubernetes cluster — for practice, use one of:
  - **Local**: `minikube start` or `kind create cluster`
  - **Cloud**: EKS (AWS), GKE (Google Cloud), or AKS (Azure) — any managed cluster works
- `helm` (package manager for Kubernetes, used for Traefik/Prometheus/cert-manager)
- A domain name you control (for TLS) — or use `nip.io` for local testing
- A GitHub account (for CI/CD)

Verify everything is installed:
```bash
docker --version
kubectl version --client
helm version
```

---

## Phase 1 — Understand the Goal Before Touching Code

You are building a system where:
1. A user visits `https://n8n.yourdomain.com`
2. Traffic hits a **Traefik ingress controller** (the "front door")
3. Traefik forwards traffic to the **n8n application pods**
4. n8n reads/writes workflow data in **Postgres** (database) and uses **Redis** (job queue)
5. Everything is **monitored** (Prometheus/Grafana), **logged** (Loki), and **backed up** (restic)
6. Any code change is **automatically tested, scanned, and deployed** by GitHub Actions

Read `docs/ARCHITECTURE.md` now — it has the diagram. Come back here after.

---

## Phase 2 — Run It Locally First (Docker Compose)

Never deploy to Kubernetes before you've proven it works locally. This is
the single biggest mistake freshers make — they skip straight to K8s and
can't tell if a bug is in their app or in their cluster config.

```bash
cd n8n-platform/docker
cp .env.example .env
```

Edit `.env` and set:
- `POSTGRES_PASSWORD` — any strong password
- `N8N_ENCRYPTION_KEY` — generate with: `openssl rand -hex 32`
- `N8N_HOST` — your domain, or `n8n.localhost` for local testing
- `ACME_EMAIL` — your email (used for Let's Encrypt notices)

Start the stack:
```bash
docker compose up -d
docker compose ps        # confirm all 4 services are "healthy"/"running"
docker compose logs -f n8n   # watch n8n boot up
```

Open `http://localhost:5678` — n8n's setup screen should appear. **This
is your proof-of-concept working.** Only move to Kubernetes once this step
succeeds cleanly.

---

## Phase 3 — Set Up the Kubernetes Cluster Basics

Install the cluster-wide tools (once per cluster):

```bash
# 1. Traefik ingress controller (via Helm)
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik -n traefik --create-namespace

# 2. cert-manager (for automatic TLS certificates)
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set installCRDs=true
```

Wait for both to report `Running`:
```bash
kubectl get pods -n traefik
kubectl get pods -n cert-manager
```

---

## Phase 4 — Deploy the Application (in this exact order)

The order matters: dependencies (database, cache) must exist before the
app that needs them.

```bash
cd n8n-platform

# 1. Namespace — isolates all our resources
kubectl apply -f k8s/00-namespace.yaml

# 2. Secrets — passwords and encryption key (EDIT VALUES FIRST!)
kubectl apply -f k8s/01-secrets.yaml

# 3. ConfigMap — non-secret settings
kubectl apply -f k8s/02-configmap.yaml

# 4. Database and cache — n8n depends on these
kubectl apply -f k8s/03-postgres-statefulset.yaml
kubectl apply -f k8s/04-redis-statefulset.yaml

# Wait until both show "1/1 Running":
kubectl get pods -n n8n-prod -w
# (press Ctrl+C once both are Running)

# 5. The n8n application itself
kubectl apply -f k8s/05-n8n-deployment.yaml
kubectl apply -f k8s/06-n8n-service.yaml
kubectl apply -f k8s/07-hpa.yaml

# 6. TLS certificate issuer, then the public route
kubectl apply -f k8s/11-cert-manager-issuer.yaml
kubectl apply -f k8s/08-ingress-traefik.yaml

# 7. Security hardening
kubectl apply -f k8s/09-networkpolicy.yaml
kubectl apply -f k8s/10-pdb.yaml
```

Check everything came up:
```bash
kubectl get all -n n8n-prod
kubectl describe certificate -n n8n-prod   # confirm TLS cert issued
```

Point your domain's DNS `A` record at your cluster's load balancer IP,
then visit `https://n8n.yourdomain.com`.

---

## Phase 5 — Set Up Monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/prometheus-values.yaml

helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack -n monitoring -f monitoring/loki-values.yaml
```

Access Grafana:
```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# open http://localhost:3000  (user: admin, password: from prometheus-values.yaml)
```
Import `monitoring/grafana-dashboard-n8n.json` under Dashboards → Import.

---

## Phase 6 — Set Up Backups

```bash
kubectl create secret generic backup-secrets -n n8n-prod \
  --from-literal=RESTIC_PASSWORD='choose-a-strong-passphrase' \
  --from-literal=AWS_ACCESS_KEY_ID='...' \
  --from-literal=AWS_SECRET_ACCESS_KEY='...'

kubectl create configmap backup-scripts -n n8n-prod --from-file=backup/backup.sh
kubectl apply -f backup/backup-cronjob.yaml
```

Test it manually before trusting the schedule:
```bash
kubectl create job --from=cronjob/n8n-nightly-backup test-backup-run -n n8n-prod
kubectl logs -n n8n-prod job/test-backup-run -f
```

---

## Phase 7 — Set Up CI/CD

1. Push this repo to GitHub.
2. In repo Settings → Secrets and variables → Actions, add:
   - `KUBE_CONFIG_B64` — your kubeconfig, base64-encoded: `cat ~/.kube/config | base64 -w0`
3. Push a commit to `main`. Watch the **Actions** tab:
   - Build → Trivy scan → Push to GHCR → `kubectl apply` → rollout verification
4. If the rollout fails, the pipeline automatically runs `kubectl rollout undo`.

---

## Phase 8 — Backup & Recovery Drill (do this once, before go-live)

1. Trigger a manual backup (Phase 6 command above).
2. Deliberately break something: `kubectl exec` into Postgres and drop a
   non-critical table, or just simulate by scaling Postgres to 0.
3. Follow the restore steps written inside `backup/backup.sh` (bottom of
   the file) to pull the latest snapshot and reload it.
4. Confirm n8n comes back up and workflows are intact.

Doing this drill **before** an actual incident is what separates a real
production system from a "hope it works" system.

---

## Phase 9 — Record the Demo Video

See `docs/DEMO_SCRIPT.md` for a scene-by-scene script covering:
architecture walkthrough → live deploy → CI/CD trigger → workflow
execution → Grafana dashboard → backup/restore proof.

---

## Common Beginner Mistakes to Avoid

1. Deploying to Kubernetes before testing locally — always prove it with
   Docker Compose first.
2. Committing real secrets to Git — always use placeholders + `.gitignore` for `.env`.
3. Applying manifests out of order — dependencies (DB/cache) before app.
4. Forgetting to change `storageClassName` in the StatefulSets to match
   your actual cluster's storage class (run `kubectl get storageclass` to check).
5. Skipping the backup/restore drill — an untested backup is not a backup.
