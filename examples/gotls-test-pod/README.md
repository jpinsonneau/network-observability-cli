# GoTLS test pod

Minimal pod that serves HTTPS with **Go `crypto/tls`** (not OpenSSL). Use it to validate NetObserv packet capture with `--enable_gotls`.

## 1. Build and push (Quay)

Same image variables as the [root Makefile](../../Makefile): `IMAGE_REGISTRY`, `IMAGE_ORG`, `VERSION`, `IMAGE`.

Default image: `quay.io/$(USER)/gotls-test:latest`

```bash
cd examples/gotls-test-pod

# log in to quay.io once (podman/docker)
podman login quay.io

# build + push
make images

# netobserv org
make images IMAGE_ORG=netobserv
# => quay.io/netobserv/gotls-test:latest

# custom tag
make images IMAGE_ORG=netobserv VERSION=decode-test
```

Build only: `make image-build`

**Local cluster only** (no registry):

```bash
make image-build IMAGE=gotls-test:latest PULL_POLICY=IfNotPresent
kind load docker-image gotls-test:latest   # Kind example
make deploy IMAGE=gotls-test:latest PULL_POLICY=IfNotPresent
```

## 2. Deploy

`make deploy` substitutes the image into the manifest (placeholders are not valid for a raw `oc apply -f deployment.yaml`).

```bash
make deploy IMAGE_ORG=netobserv
make wait
export GOTLS_POD_IP=$(make pod-ip)
echo "Pod IP: $GOTLS_POD_IP"
```

## 3. Generate HTTPS traffic

```bash
make traffic
# or one-off:
oc run -n gotls-test curl-once --rm -it --restart=Never \
  --image=curlimages/curl:8.11.1 --command -- \
  curl --http1.1 -sk "https://${GOTLS_POD_IP}:8443/message?seq=1"
```

Expected response body (unique `NETOBSERV-GOTLS` marker; `seq` and `time` change each request):

```text
NETOBSERV-GOTLS plaintext probe
TLS stack: Go crypto/tls (writeRecordLocked)
Workload: gotls-test-pod
Endpoint: GET /message
Capture hint: look for "NETOBSERV-GOTLS" in PlaintextPreview
seq=1 time=2026-...
```

`make traffic` also hits `/api/items` (JSON with `"sku":"gotls-epsilon"`) and `POST /api/echo`, which echoes the client body and **received request headers** in the response.

Fake HTTP headers (`X-NetObserv-Stack`, `X-Fake-Authorization`, `X-Fake-Trace-Id`, …) are set on every response so `PlaintextPreview` shows realistic `HTTP/1.1 200 OK` blocks in the live view.

## 4. Capture with NetObserv

Agent image must include GoTLS support, PID-scope gate, and the register-ABI BPF fix in `bpf/gotls_tracker.h` (rebuild with `make docker-generate` after pulling latest agent).

```bash
./build/oc-netobserv packets \
  --port=8443 \
  --peer_ip="${GOTLS_POD_IP}" \
  --enable_gotls \
  --privileged \
  --max-bytes=100000000
```

`--enable_gotls` captures **server response** plaintext (`Direction: write`, e.g. `HTTP/1.1 200 OK`). Inbound HTTP requests are not captured yet — `Read` uprobes crash Go `crypto/tls` workloads.

Keep traffic running while capture is active (`make traffic` or repeated `curl`).

## 5. Verify GoTLS plaintext

**JSONL** (`output/plaintext/*.jsonl`):

```bash
jq 'select(.TLSSource == "gotls")' output/plaintext/*.jsonl
```

Expect `"TLSSource": "gotls"` and `PlaintextPreview` containing `NETOBSERV-GOTLS` (HTTP responses).

**Agent logs** (DaemonSet on the node where the pod runs):

```bash
oc logs -n netobserv-cli daemonset/netobserv-cli | grep -i gotls
```

Look for `attached GoTLS write uprobe` and `GoTLS uprobe attachment count`.

## Makefile reference

| Variable | Default | Example |
|----------|---------|---------|
| `IMAGE_REGISTRY` | `quay.io` | `docker.io` |
| `IMAGE_ORG` | `$(USER)` | `netobserv` |
| `VERSION` | `latest` | `decode-test` |
| `IMAGE` | `$(IMAGE_REGISTRY)/$(IMAGE_ORG)/gotls-test:$(VERSION)` | full override |
| `PULL_POLICY` | `Always` | `IfNotPresent` (local) |

Run `make help` for targets (`images`, `image-build`, `image-push`, `deploy`, …).

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `ImagePullBackOff` | `make images` and `make deploy` use the same `IMAGE`; repo is public or cluster has pull secret |
| Job `Forbidden` / SCC `runAsUser` | OpenShift assigns UIDs per namespace; manifests omit fixed `runAsUser` and set `hostUsers: false` |
| `CrashLoopBackOff` / SIGSEGV in `tls.(*Conn).Read` | Agent has `GOTLS_CAPTURE_READ=true` (read uprobes). **Redeploy capture without it** — CLI `--enable_gotls` no longer sets that env. If you patched the DaemonSet manually, set `GOTLS_CAPTURE_READ=false` and restart the agent pod on the gotls node |
| No `gotls` in JSONL | Use a **custom agent image**; `peer_ip` should be the **server pod IP** (recommended); agent DaemonSet on the **same node**; `--enable_gotls --privileged`; keep traffic during capture. Agent logs should show `attached GoTLS write uprobe` |
| No green rows with `--enable_openssl` | **Wrong flag** — this pod uses Go `crypto/tls`, not OpenSSL. Use `--enable_gotls` instead |
| Unscoped GoTLS warning | Expected without `--peer_ip` — add `--peer_ip=<pod-ip>` to narrow hooks to the target pod |
| Only `openssl` events | Traffic terminated by OpenSSL sidecar/ingress, not Go `crypto/tls` in target PID |

## Cleanup

```bash
make undeploy
```

## OpenSSL variant

This pod does **not** use libssl. For OpenSSL capture, use [openssl-test-pod](../openssl-test-pod/) with `--enable_openssl`.
