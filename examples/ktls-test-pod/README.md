# kTLS test pod

Minimal pod that serves HTTPS with **nginx + kernel TLS (kTLS) offload** via OpenSSL 3. Use it to validate NetObserv packet capture with `--enable_ktls`.

Unlike [gotls-test-pod](../gotls-test-pod/), this workload does **not** use Go `crypto/tls` or userspace-only TLS — plaintext is visible to the agent only when the **node kernel** offloads TLS to kTLS (`sk_msg` hook).

## Requirements

| Layer | Requirement |
|-------|-------------|
| Node kernel | Linux 5.2+ with **kTLS built in** (`CONFIG_TLS=y` or `tls` module loaded). In the **workload pod** during traffic: `kubectl exec -n ktls-test deploy/ktls-test -- cat /proc/net/tls_stat` — `TlsTxSw` / `TlsRxSw` should increase (there is no `/proc/net/tls` on recent Fedora/RHEL kernels) |
| OpenSSL | 3.x with kTLS enabled (Fedora/RHEL nginx images) |
| Agent | Image with kTLS BPF fix + `ENABLE_KTLS_TRACKING`; cgroup v2 on the node |
| Capture | `--enable_ktls --privileged` (host cgroup mount + sockops/sk_msg; sets `KTLS_CGROUP_ROOT=/host-cgroup`) |

The nginx config pins **TLS 1.2 only** with AES-GCM ciphers. Kernel TLS offload on RHEL/Linux does not cover TLS 1.3 or non-AEAD suites — those stay in userspace OpenSSL and will not produce kTLS plaintext for the agent. The bundled traffic Job uses `curl --tlsv1.2 --tls-max 1.2` for the same reason.

Kind/minikube work when the **host** kernel supports kTLS (typical on recent Fedora/RHEL). Alpine or OpenSSL 1.1-only images will not enable kTLS.

## 1. Build and push (Quay)

Same image variables as the [root Makefile](../../Makefile): `IMAGE_REGISTRY`, `IMAGE_ORG`, `VERSION`, `IMAGE`.

Default image: `quay.io/$(USER)/ktls-test:latest`

```bash
cd examples/ktls-test-pod

podman login quay.io   # or docker login

make images

make images IMAGE_ORG=netobserv
# => quay.io/netobserv/ktls-test:latest
```

Build only: `make image-build`

**Local Kind cluster** (private Quay repo — nodes cannot pull without credentials):

```bash
make image-build USER=jpinsonn VERSION=test
make deploy-local USER=jpinsonn VERSION=test
# or manually:
kind load docker-image quay.io/jpinsonn/ktls-test:test --name netobserv-cli-cluster
make deploy USER=jpinsonn VERSION=test PULL_POLICY=IfNotPresent
```

**OpenShift / shared cluster** — make the Quay repository **public**, or link a pull secret to the `ktls-test` namespace:

```bash
# Quay: Repository Settings → make public (same as gotls-test)
# or:
oc create secret docker-registry quay-jpinsonn \
  --docker-server=quay.io --docker-username=... --docker-password=... \
  -n ktls-test
oc secrets link default quay-jpinsonn --for=pull -n ktls-test
make deploy USER=jpinsonn VERSION=test
```

## 2. Deploy

`make deploy` substitutes the image into the manifest (placeholders are not valid for a raw `oc apply -f deployment.yaml`).

```bash
make deploy IMAGE_ORG=netobserv
make wait
export KTLS_POD_IP=$(make pod-ip)
echo "Pod IP: $KTLS_POD_IP"
```

## 3. Generate HTTPS traffic

```bash
make traffic
# or one-off:
oc run -n ktls-test curl-once --rm -it --restart=Never \
  --image=curlimages/curl:8.11.1 --command -- \
  curl --http1.1 --tlsv1.2 --tls-max 1.2 -sk "https://${KTLS_POD_IP}:8443/message"
```

Expected response body (unique `NETOBSERV-KTLS` marker):

```text
NETOBSERV-KTLS plaintext probe
TLS stack: nginx + OpenSSL kTLS kernel offload (sk_msg)
Workload: ktls-test-pod
Endpoint: GET /message
Capture hint: look for "NETOBSERV-KTLS" in PlaintextPreview
```

`make traffic` also hits `/api/items` (JSON with `"sku":"ktls-gamma"`) and `POST /api/echo` with client body `NETOBSERV-KTLS client request seq=N`.

Response fake headers (`X-NetObserv-Stack: ktls`, `X-Fake-Trace-Id: ktls-resp-message`, …) should appear in kTLS `PlaintextPreview` alongside the HTTP status line.

## 4. Capture with NetObserv

### OpenSSL uprobes (recommended for TLS plaintext today)

Use the dedicated [openssl-test-pod](../openssl-test-pod/) — nginx **without** kTLS offload, so `SSL_write` uprobes always see application data.

```bash
cd examples/openssl-test-pod && make deploy && make wait
export OPENSSL_POD_IP=$(make pod-ip)
NETOBSERV_AGENT_IMAGE=quay.io/jpinsonn/netobserv-ebpf-agent:decode-62 \
  ./build/oc-netobserv packets \
  --port=8443 \
  --peer_ip="${OPENSSL_POD_IP}" \
  --enable_openssl \
  --privileged \
  --max-bytes=100000000
```

Expect `"TLSSource": "openssl"` in JSONL.

On **this** ktls-test pod (kTLS enabled in nginx), OpenSSL uprobes may still miss data when the kernel offloads TLS. Prefer openssl-test-pod for `--enable_openssl` validation.

### kTLS sk_msg (experimental)

Agent image needs kTLS BPF fixes (`bpf/ktls_tracker.h` verifier fix, `PlaintextScope` kTLS bypass, `kubepods.slice` sockops cgroup on Kubernetes).

```bash
NETOBSERV_AGENT_IMAGE=quay.io/jpinsonn/netobserv-ebpf-agent:decode-40 \
  ./build/oc-netobserv packets \
  --port=8443 \
  --peer_ip="${KTLS_POD_IP}" \
  --enable_ktls \
  --privileged \
  --max-bytes=100000000
```

`--enable_ktls` captures **outbound** kernel-offloaded TLS (`Direction: write`). Keep `make traffic` running during capture.

Agent logs should show `TLS plaintext event captured` with `source=ktls` when sk_msg capture works. If hooks attach but this line never appears, prefer `--enable_openssl` above.

After agent start, look for periodic **`kTLS BPF stats`** or **`kTLS BPF idle`** log lines:

```bash
kubectl logs -n netobserv-cli daemonset/netobserv-cli | rg 'kTLS (BPF stats|BPF idle|sockops attached)'
```

| Stats | Meaning |
|-------|---------|
| `sockops_established=0` | Agent cgroup namespace isolated — redeploy capture with latest CLI (`KTLS_CGROUP_ROOT=/host-cgroup` mount); use `--peer_ip` |
| `sockops>0`, `sk_msg_enter=0` | Sockets missed `sock_hash` before kTLS offload — **restart traffic after agent** |
| `sk_msg_enter>0`, `sk_msg_captured=0` | sk_msg fires but plaintext read failed |
| `sk_msg_captured>0` | BPF works — check JSONL / `PlaintextScope` filters |

**Critical:** kTLS BPF only hooks sockets added to `sock_hash` at TCP `ESTABLISHED` **before** OpenSSL enables kernel offload. If traffic started before the agent, delete the traffic job and rerun:

```bash
kubectl delete job -n ktls-test ktls-test-traffic --ignore-not-found
make traffic
```

## 5. Verify kTLS plaintext

**JSONL** (`output/plaintext/*.jsonl`):

```bash
jq 'select(.TLSSource == "ktls")' output/plaintext/*.jsonl
```

Expect `"TLSSource": "ktls"` and `PlaintextPreview` containing `ktls-test-pod`.

**Agent logs** (DaemonSet on the node where the pod runs):

```bash
oc logs -n netobserv-cli daemonset/netobserv-cli | grep -i ktls
```

Look for `kTLS tracking enabled with cgroup and sk_msg hooks` at startup (no BPF verifier crash).

**Optional — confirm kTLS on the node** (while traffic is active):

```bash
# on the worker node hosting the pod
sudo cat /proc/net/tls
```

Non-empty output indicates kernel TLS contexts are active.

## Makefile reference

| Variable | Default | Example |
|----------|---------|---------|
| `IMAGE_REGISTRY` | `quay.io` | `docker.io` |
| `IMAGE_ORG` | `$(USER)` | `netobserv` |
| `VERSION` | `latest` | `decode-test` |
| `IMAGE` | `$(IMAGE_REGISTRY)/$(IMAGE_ORG)/ktls-test:$(VERSION)` | full override |
| `PULL_POLICY` | `Always` | `IfNotPresent` (local) |

Run `make help` for targets (`images`, `image-build`, `image-push`, `deploy`, …).

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `ImagePullBackOff` / `401 UNAUTHORIZED` | Quay repo is **private** — Kind has no pull secret. Use `make deploy-local` (Kind) or make the repo public on quay.io (OpenShift) |
| `CreateContainerConfigError` / `non-numeric user (nginx)` | Rebuild image after Dockerfile fix (`USER 65534:0`); older tags used named `nginx` user |
| `Permission denied` on `/tmp/tls/key.pem` or `/var/log/nginx/error.log` | OpenShift arbitrary UID — rebuild image (`chmod a+rwX` on tls/nginx paths); redeploy with `fsGroup: 0` in manifest |
| Agent `CrashLoopBackOff` on `--enable_ktls` | Agent missing kTLS BPF fix; rebuild with `make docker-generate` |
| HTTPS works but no `ktls` in JSONL | Node kernel lacks kTLS (`/proc/net/tls` missing on workers — common on RHCOS/OpenShift 4.x). nginx falls back to userspace TLS; use `--enable_openssl` for this pod instead, or test on Fedora/Kind with kTLS |
| Only `openssl` / `gotls` events | Wrong flag — this pod needs `--enable_ktls`, not `--enable_openssl` or `--enable_gotls` |
| Kind local image | `kind load docker-image` + `PULL_POLICY=IfNotPresent` on deploy and agent DaemonSet |

## Cleanup

```bash
make undeploy
```

## OpenShift / RHCOS note

Many OpenShift worker kernels (e.g. RHEL 9.6 `5.14.0-570.x`) ship **without** the kernel `tls` module — `/proc/net/tls` does not exist and nginx cannot offload TLS to kTLS even with `ssl_conf_command Options KTLS`.

On those clusters, `ktls-test` still serves HTTPS but `--enable_ktls` will not produce plaintext. Use [openssl-test-pod](../openssl-test-pod/) with `--enable_openssl` instead.

## Related

- [OpenSSL test pod](../openssl-test-pod/) — userspace OpenSSL / nginx (`--enable_openssl`)
- [GoTLS test pod](../gotls-test-pod/) — userspace Go `crypto/tls` (`--enable_gotls`)
- [TLS decryption coverage](../../docs/tls-decryption-coverage.md)
