# Radicle Seed Helm Chart

Deploys one persistent [Radicle](https://radicle.dev/) seed node, its read-only `radicle-httpd` API, and a [Radicle Explorer](https://github.com/radicle-dev/radicle-explorer) web frontend by default. It follows the [Radicle Seeder Guide](https://radicle.dev/guides/seeder) while adapting the service-manager design to Kubernetes.

## Design

- A single-replica `StatefulSet` retains the Radicle identity, storage, database, and sockets on one PVC. A Radicle identity must not be recreated when a pod is rescheduled.
- `radicle-node` listens on TCP `8776` and is exposed by a dedicated `LoadBalancer` or `NodePort` Service. The advertised `node.externalAddresses` must point to this public endpoint.
- `radicle-httpd` shares that PVC read-only and is only reachable through a `ClusterIP` Service. Explorer is served at the Ingress root, while `/api` and `/raw` are routed to HTTPD; the chart never exposes HTTP port `8080` through the P2P Service.
- Explorer is a separate static deployment with runtime configuration. It uses the same HTTPS host as HTTPD and is enabled by default when HTTPD is enabled.
- Optional Meilisearch support runs a `radicle-search` sidecar alongside the node and HTTP daemon. It continuously indexes seeded public repositories and lets HTTPD provide fast, typo-tolerant repository search.
- The seed pod meets the restricted Pod Security Standard: non-root UID/GID `10000`, no capabilities, no privilege escalation, a read-only root filesystem, `RuntimeDefault` seccomp, no service-account token, and memory-backed `/tmp`. The Explorer and Meilisearch pods are also restricted-compliant and run read-only root filesystems, but under the UIDs their upstream images expect (`101` and `1000` respectively) rather than `10000`.
- The default seeding policy is **selective** (`block`). This avoids silently opting an operator into replicating arbitrary permissionless data. A permissive public seed is supported as an explicit value change.

The default seed and Explorer images are published to a public registry so that clusters with no route to a private registry can pull them. Their recipes live in `images/`: the seed image verifies upstream Radicle release signatures and includes `rad`, `radicle-node`, `radicle-httpd`, and `radicle-search`; the Explorer image builds a pinned upstream revision with runtime configuration enabled. Both are published as `linux/amd64` and `linux/arm64` manifests.

Images are versioned and released **independently of this chart**, so their tags track the upstream versions they package rather than the chart version, and a template-only chart fix does not force an image rebuild. See [Releasing](#releasing).

## Prerequisites

- Kubernetes 1.25 or newer, a default `StorageClass` or `persistence.storageClass`, and enough persistent storage. The Seeder Guide suggests at least 10 GB; this chart requests 20 Gi by default.
- A public static IP or a TCP-capable load balancer for port `8776`, plus a DNS name pointing to it.
- Firewall and cloud security-group rules allowing inbound **TCP 8776** to the node service. If using the HTTP API publicly, the Ingress controller must allow inbound TCP `443`.
- An Ingress controller and TLS certificate management if the HTTP API should be browsable through Radicle Explorer or another web frontend.

The chart creates an identity only on a new PVC. It deliberately does not generate a passphrase: the passphrase and identity are security-critical persistent state.

## Install

Create a strong passphrase secret outside Helm. This avoids retaining a secret in Helm release values:

```sh
kubectl create namespace radicle
kubectl -n radicle create secret generic radicle-seed-auth \
  --from-literal=RAD_PASSPHRASE="$(openssl rand -base64 48)"
```

Create a values file from the public example, replacing its placeholder domain, load-balancer annotations, and TLS settings. For a private or community seed, start with `examples/selective-seed-values.yaml` instead.

```sh
helm upgrade --install seed . \
  --namespace radicle \
  --values examples/public-seed-values.yaml
```

The chart intentionally refuses to render until it has both a passphrase source and at least one advertised external address. This prevents an apparently successful installation from creating an unrecoverable identity or a node that peers cannot reach.

The essential settings are:

```yaml
auth:
  existingSecret: radicle-seed-auth
node:
  alias: seed.example.com
  externalAddresses:
    - seed.example.com:8776
```

`node.externalAddresses` is not inferred from a Kubernetes Service. It must exactly match a DNS name and TCP port that peers on the public internet can reach. Set it before the first deployment and do not use a pod IP or a ClusterIP address.

For an ad-hoc test only, Helm can create the passphrase Secret by setting `auth.passphrase`. Do not use this for production because Helm stores the supplied value in the release record.

```sh
helm upgrade --install seed . --namespace radicle --create-namespace \
  --set auth.passphrase='replace-with-a-long-random-value' \
  --set node.alias=seed.example.com \
  --set-json 'node.externalAddresses=["seed.example.com:8776"]'
```

## Seeding Policy

The default configuration is selective:

```yaml
node:
  seedingPolicy:
    default: block
```

Allow particular repositories after the node is ready:

```sh
kubectl -n radicle exec statefulset/seed-radicle-seed -c node -- \
  rad seed rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5
```

For a public, fully-replicating seed, explicitly accept the legal and operational implications described in the Seeder Guide, then use:

```yaml
node:
  seedingPolicy:
    default: allow
    scope: all
```

You can still exclude an individual repository from a permissive seed with `rad block <RID>`, and remove an override with `rad unseed <RID>`. The per-repository policy database is stored on the PVC.

## Explorer, HTTP API, And TLS

With `httpd.enabled=true`, the daemon binds to port `8080` inside the pod but its Service is `ClusterIP`, so it is not public by default. Explorer is enabled by default and its Service receives the Ingress root path. The Ingress routes `/api` and `/raw` to HTTPD so Explorer can query the API and browse repository content.

Set `ingress.enabled=true` only with an Ingress controller that terminates TLS and a valid certificate. The `examples/public-seed-values.yaml` file shows the required host and TLS shape; controller-specific certificate annotations remain operator-owned.

The same DNS name may serve both the P2P node on `:8776` and the HTTPS API on `:443`. The P2P service remains separate from the Ingress because the Radicle protocol is not HTTP.

## Search

Set `search.enabled=true` to deploy Meilisearch and the `radicle-search` sidecar. Provide `search.existingSecret`, whose `MEILI_MASTER_KEY` key is passed to Meilisearch, HTTPD, and the indexer. The chart keeps Meilisearch internal; only HTTPD communicates search results to Explorer through the existing API.

The indexer only indexes **public** repositories that the node seeds. Private repositories remain unindexed even when search is enabled. HTTPD falls back to its storage walk if Meilisearch is unavailable, so repository browsing remains available while search recovers.

## Verify And Operate

```sh
kubectl -n radicle get pods,svc
kubectl -n radicle logs statefulset/seed-radicle-seed -c node --follow
kubectl -n radicle exec statefulset/seed-radicle-seed -c node -- rad node status
kubectl -n radicle exec statefulset/seed-radicle-seed -c node -- rad node config --addresses
```

The last command returns the node address to share with peers. Once HTTPS is configured, verify the read-only API externally:

```sh
curl https://seed.example.com/api/v1
```

Changing Helm values updates the ConfigMap and its checksum, rolling the `StatefulSet` so `radicle-node` reloads `config.json`. `config.extra` can add unsupported top-level and `node` settings, but chart-managed alias, listener, advertised address, and seeding-policy settings always take precedence. The bundled HTTP daemon always listens on `8080`. Monitor storage capacity, bandwidth, and memory closely for permissive seeds, as their replicated data set can grow without a fixed bound.

Back up the PVC **and** retain the passphrase Secret. Restoring only one is insufficient to recover an encrypted node identity. Never scale this chart above one replica against the same PVC; a Radicle seed identity and its local storage are single-writer state.

## DNS-Based Discovery

DNS-based service discovery is optional. After retrieving the Node ID with `rad self --nid`, create the guide's SRV, TXT, and PTR records for the domain used to discover the node. For a Node ID `z6Mk...`, address `seed.example.com:8776`, and discovery domain `example.com`:

```zone
seed._radicle-node._tcp.example.com. 3600 IN SRV 32767 32767 8776 seed.example.com.
seed._radicle-node._tcp.example.com. 3600 IN TXT "nid=z6Mk..."
_radicle-node._tcp.example.com.      3600 IN PTR seed._radicle-node._tcp.example.com.
```

DNS-SD is an addition to, not a replacement for, the `node.externalAddresses` setting.

## Releasing

Charts and images are released by separate, independently triggered GitHub Actions workflows. Both publish to GHCR under the repository owner using the built-in `GITHUB_TOKEN`, so no registry secret needs configuring. The `REGISTRY` and `REGISTRY_NAMESPACE` repository variables can override the destination without editing a workflow.

**Images** are tagged `images/<image>/v<version>`, where the version identifies what the image packages:

```sh
git tag images/radicle-seed/v1.9.1            # matches RADICLE_VERSION
git tag images/radicle-explorer/v0.18.0-53730d4  # API version + pinned EXPLORER_REV
git push origin --tags
```

The Containerfile `ARG`s remain the source of truth for the contents; the tag labels them. Each architecture builds on a native runner (`ubuntu-latest` and `ubuntu-24.04-arm`) and is pushed by digest, then a manifest list is assembled from those digests, so nothing is emulated. The run summary reports the final manifest digest — pin it in `values.yaml` under `image.digest` / `explorer.image.digest` for immutable production deployments.

Native `arm64` runners are only free on public repositories. On a private repository the `linux/arm64` leg will not get a free runner.

**Charts** keep the existing `<chart>/v<version>` tag form, and the tag version must match `Chart.yaml`:

```sh
git tag radicle-seed/v0.1.0
git push origin --tags
```

This workflow runs no Docker at all. It lints, packages, verifies that no build context leaked into the tarball and that every image the chart references is resolvable by consumers, then pushes to `oci://<registry>/<namespace>/helm-charts`.
