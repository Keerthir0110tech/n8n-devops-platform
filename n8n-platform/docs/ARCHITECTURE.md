# Solution Architecture — AI Automation Platform (n8n)

## 1. Diagram

```
                              ┌─────────────────────────┐
                              │        End Users        │
                              └────────────┬─────────────┘
                                           │ HTTPS
                                           ▼
                              ┌─────────────────────────┐
                              │   DNS (Cloudflare)      │
                              │  n8n.yourdomain.com     │
                              └────────────┬─────────────┘
                                           ▼
                       ┌───────────────────────────────────────┐
                       │     Cloud Load Balancer (L4/L7)        │
                       └────────────────────┬────────────────────┘
                                            ▼
        ┌───────────────────────────────────────────────────────────────┐
        │                    Kubernetes Cluster (EKS/GKE/AKS)             │
        │   Multi-AZ, 3+ worker nodes, autoscaling node group             │
        │                                                                 │
        │  ┌───────────────── namespace: traefik ─────────────────┐      │
        │  │  Traefik Ingress Controller (Deployment, 2 replicas)  │      │
        │  │  cert-manager → Let's Encrypt ACME HTTP-01            │      │
        │  └────────────────────────┬───────────────────────────────┘    │
        │                           ▼                                    │
        │  ┌───────────────── namespace: n8n-prod ────────────────┐      │
        │  │  IngressRoute → Service (n8n-svc) → Deployment (n8n)  │      │
        │  │    - 2..6 replicas (HPA on CPU/mem)                   │      │
        │  │    - queue mode via Redis (Bull MQ)                   │      │
        │  │  StatefulSet: postgres (PVC, single primary)          │      │
        │  │  StatefulSet: redis (PVC, AOF persistence)            │      │
        │  │  NetworkPolicy: default-deny + explicit allow         │      │
        │  │  PodDisruptionBudget: minAvailable 1                  │      │
        │  │  CronJob: nightly backup (pg_dump + restic → S3)      │      │
        │  └─────────────────────────────────────────────────────────┘   │
        │                                                                 │
        │  ┌───────────────── namespace: monitoring ───────────────┐     │
        │  │  Prometheus + Alertmanager  (metrics + alert routing)  │     │
        │  │  Grafana                    (dashboards)               │     │
        │  │  Loki + Promtail            (centralized logs)         │     │
        │  └─────────────────────────────────────────────────────────┘   │
        └───────────────────────────────────────────────────────────────┘
                                            │
                                            ▼
                              ┌─────────────────────────┐
                              │   S3 / Object Storage    │
                              │   (encrypted backups)    │
                              └─────────────────────────┘

        CI/CD:  GitHub → GitHub Actions → Build+Scan(Trivy) → GHCR
                → kubectl apply / helm upgrade → Rolling deploy → Verify
```

## 2. Design Decisions & Rationale

| Decision | Why |
|---|---|
| Kubernetes over plain Docker hosts | Self-healing, rolling updates, HPA, declarative config, matches "enterprise-grade" requirement |
| Traefik over Nginx | Native Kubernetes CRDs (IngressRoute), built-in Let's Encrypt integration, dynamic config reload without restarts |
| n8n queue mode (Redis + Bull) | Decouples webhook intake from execution; lets worker pods scale independently and survive pod restarts without losing in-flight jobs |
| Postgres over SQLite | SQLite is single-file/single-writer — unsuitable once n8n runs as multiple replicas; Postgres supports concurrent access and is the documented production backend for n8n |
| StatefulSet + PVC for DB | Stable network identity and durable storage across pod rescheduling |
| Default-deny NetworkPolicy | Zero-trust inside the cluster — every allowed path is explicit and auditable |
| GHCR + Trivy scan gate in CI | Fails the pipeline on CRITICAL/HIGH CVEs before an image ever reaches production |
| Prometheus + Grafana + Loki | Industry-standard, open-source, avoids vendor lock-in; single pane of glass for metrics + logs |
| restic + S3 backups | Encrypted, deduplicated, incremental backups with simple retention policies and fast restore |

## 3. Scaling & High Availability

- **n8n app tier**: stateless, horizontally scaled via HPA (CPU/mem), fronted by a ClusterIP Service; Traefik load-balances across all ready pods.
- **Database tier**: single primary Postgres for this assignment scope; production-grade upgrade path is a managed service (RDS/Cloud SQL) with a read replica and automated failover.
- **Multi-AZ nodes**: scheduler spreads pods across availability zones using topology spread constraints (add `topologySpreadConstraints` to the Deployment for real multi-AZ resilience).
- **PodDisruptionBudget**: guarantees at least 1 n8n pod stays up during voluntary disruptions (node drains, upgrades).

## 4. Security Model

1. **Transport**: TLS 1.2+ everywhere, auto-renewed certs via cert-manager.
2. **Network**: default-deny NetworkPolicy; only Traefik and monitoring namespaces may reach n8n pods; n8n may only reach Postgres, Redis, DNS, and HTTPS egress (for webhook/API calls).
3. **Identity**: containers run as non-root (UID 1000), `allowPrivilegeEscalation: false`, capabilities dropped.
4. **Secrets**: Kubernetes Secrets as a baseline; recommend upgrading to Sealed Secrets or External Secrets Operator backed by a cloud secret manager for real production use — plaintext Secrets in etcd are not sufficient alone.
5. **Supply chain**: Trivy scan gate in CI blocks vulnerable images from being pushed.
6. **Edge protection**: Traefik middleware adds security headers (HSTS, X-Frame-Options, nosniff) and rate limiting.

## 5. Observability

- **Metrics**: n8n exposes Prometheus metrics (`/metrics`) — execution counts, error rate, queue depth — scraped and visualized in Grafana.
- **Logs**: Promtail ships container stdout/stderr to Loki, queryable in Grafana Explore, labeled by namespace/pod.
- **Alerting**: Alertmanager routes critical alerts (pod crash-looping, high error rate, disk pressure) to Slack.

## 6. Backup & Recovery

- Nightly `pg_dump` of the Postgres database, compressed and pushed via `restic` to S3 with deduplication and 30-day tiered retention (7 daily / 4 weekly / 6 monthly).
- The n8n encryption key is backed up separately and is required to decrypt stored workflow credentials on restore.
- Recovery target: RPO ≤ 24h, RTO ≤ 30 minutes (documented step-by-step in `backup/backup.sh`).
