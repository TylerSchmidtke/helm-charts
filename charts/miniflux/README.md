# Miniflux Helm Chart

Deploys [Miniflux](https://miniflux.app/), a minimalist feed reader, as a single stateless Deployment backed by an external PostgreSQL database.

## Design

- Miniflux keeps **all** state in PostgreSQL. It has no SQLite support: upstream links only `github.com/lib/pq`, and `DATABASE_URL` is a PostgreSQL connection string. This chart therefore provisions no `PersistentVolumeClaim`, and a reachable PostgreSQL server is a hard prerequisite.
- The Deployment is pinned to **one replica** with the **`Recreate`** strategy, and neither is configurable. Miniflux selects feeds to poll with `next_check_at < now()` and takes no row lock, so a second replica re-polls every due feed: duplicate outbound requests to each publisher and a race on entry insertion. `Recreate` additionally guarantees a new pod never runs migrations against a schema the outgoing pod is still serving.
- Probes use Miniflux's **root-level** endpoints. `/liveness` is a static handler; `/readiness` pings the database. Using the database-backed check for liveness would turn a brief PostgreSQL outage into a restart loop, so only readiness depends on the database. These endpoints are also served outside the base path, so probes keep working when `miniflux.baseUrl` contains a subpath — unlike `/healthcheck`, which moves with `BASE_URL`.
- A startup probe absorbs the migration window, so a slow migration on a large database is not mistaken for a hung process.
- The pod meets the restricted Pod Security Standard: non-root UID/GID `65534` matching the upstream image's `USER` directive, no capabilities, no privilege escalation, a read-only root filesystem, `RuntimeDefault` seccomp, and no service-account token. `/tmp` is memory-backed because Go spills large multipart uploads, such as an OPML import, to the temporary directory.

## Prerequisites

- Kubernetes 1.25 or newer.
- A PostgreSQL server reachable from the cluster, with a database and role for Miniflux. The chart does not deploy one; pair it with a PostgreSQL operator or a managed instance.
- An Ingress controller and TLS certificate management if Miniflux should be reachable from a browser. Miniflux authenticates with a session cookie, so the chart refuses to render an Ingress without TLS.

## Install

Create the credentials outside Helm. Helm records supplied values in the release, so `existingSecret` is the preferred path for anything sensitive:

```sh
kubectl create namespace miniflux
kubectl -n miniflux create secret generic miniflux-credentials \
  --from-literal=DATABASE_URL='postgres://miniflux:secret@postgres:5432/miniflux?sslmode=require' \
  --from-literal=ADMIN_PASSWORD="$(openssl rand -base64 24)"
```

```sh
helm upgrade --install miniflux . \
  --namespace miniflux \
  --set existingSecret=miniflux-credentials \
  --set miniflux.baseUrl=https://miniflux.example.com \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set 'ingress.hosts[0].host=miniflux.example.com' \
  --set 'ingress.tls[0].secretName=miniflux-tls' \
  --set 'ingress.tls[0].hosts[0]=miniflux.example.com'
```

If the Secret uses different key names, point the chart at them with `existingSecretDatabaseUrlKey` and `existingSecretAdminPasswordKey`.

For a quick local trial you can let the chart create the Secret instead, accepting that both values are stored in the release:

```sh
helm upgrade --install miniflux . \
  --namespace miniflux \
  --set miniflux.databaseUrl='postgres://miniflux:secret@postgres:5432/miniflux?sslmode=disable' \
  --set miniflux.adminPassword='change-me'
```

## The Admin User

`miniflux.adminPassword` is used **only** to create the first admin user, on the first run against an empty database. Upstream `createAdminUser` skips creation when the username already exists, so changing this value later does **not** rotate the password — the change is silently ignored.

To rotate the admin password, change it in the web UI. Once the admin user exists, set:

```yaml
miniflux:
  createAdmin: false
```

This drops `ADMIN_USERNAME` and `ADMIN_PASSWORD` from the pod entirely and stops requiring the value. Upstream recommends the same cleanup after initialization.

## Base URL And Subpaths

Set `miniflux.baseUrl` to the full public URL, with a scheme and no trailing slash. Miniflux derives its internal base path from this value, so `https://example.com/miniflux` serves the application under `/miniflux`. The chart's probes are unaffected because `/liveness` and `/readiness` are always mounted at the server root.

## Upgrades

`miniflux.runMigrations` defaults to `true`. Miniflux refuses to start when the schema does not match the binary, so leave this enabled when bumping `appVersion`. Because the strategy is `Recreate`, expect a short outage during upgrades while the old pod stops and the new one migrates.

Take a database backup before an upgrade. The chart holds no state and can be reinstalled freely; PostgreSQL is the only thing that matters.

## Additional Configuration

Any Miniflux configuration parameter not modelled by this chart can be passed through:

```yaml
miniflux:
  extraEnv:
    - name: POLLING_FREQUENCY
      value: "60"
    - name: METRICS_COLLECTOR
      value: "1"
```

See the [Miniflux configuration reference](https://miniflux.app/docs/configuration.html). Do not put secrets in `extraEnv` as literal values; use `valueFrom` with a `secretKeyRef`, which the schema permits.

## Releasing

Charts are released by the `release-chart.yml` workflow, triggered by a tag whose version must match `Chart.yaml`:

```sh
git tag miniflux/v0.1.0
git push origin --tags
```

The workflow lints, packages, verifies that no build context leaked into the tarball, and pushes to `oci://<registry>/<namespace>/helm-charts`.
