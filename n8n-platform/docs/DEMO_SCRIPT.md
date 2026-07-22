# Demo Video Script (5–10 minutes)

Record your screen with narration. Suggested timing below — adjust to fit.

**0:00–1:00 — Introduction & Architecture (talk over the diagram)**
"This is a production deployment of an n8n AI automation platform on
Kubernetes. Traffic enters through Traefik with automatic TLS, hits n8n
running in queue mode backed by Postgres and Redis, and the whole system
is monitored with Prometheus/Grafana and backed up nightly to S3."
→ Show `docs/ARCHITECTURE.md` diagram on screen.

**1:00–2:30 — Repository Walkthrough**
Show the folder structure: `docker/`, `k8s/`, `ci-cd/`, `monitoring/`,
`backup/`, `docs/`. Briefly explain what each holds.

**2:30–4:30 — Live Deployment**
```bash
kubectl apply -f k8s/
kubectl get pods -n n8n-prod -w
```
Show pods transitioning to `Running`. Open `https://n8n.yourdomain.com`
in a browser to prove it's live with a valid TLS padlock.

**4:30–6:00 — CI/CD in Action**
Make a trivial code change (e.g. bump a label), commit, push to `main`.
Switch to GitHub → Actions tab and show the pipeline running: build →
Trivy scan → push to GHCR → deploy → rollout status. Show the green checkmark.

**6:00–7:30 — Monitoring & Logging**
Open Grafana, show the n8n dashboard (execution rate, CPU/memory, HPA
replica count). Open Loki/Explore and show a live log query filtered to
the `n8n-prod` namespace.

**7:30–9:00 — A Real Workflow + Backup Proof**
Trigger a simple n8n workflow (e.g. a webhook → HTTP request) to prove
the app actually functions end-to-end. Then run the manual backup job and
show the snapshot listed via `restic snapshots`.

**9:00–10:00 — Wrap-up**
Summarize: scalable (HPA), secure (TLS + NetworkPolicy + non-root), observable
(Prometheus/Grafana/Loki), automated (GitHub Actions), and recoverable
(nightly backups with a tested restore path). Point to the README for
full setup instructions.
