# Evidence log

[Milestone 1](milestone-1.md) · [Architecture](architecture.md) · [README](../README.md)

Observed results only. Each entry records platform, actions and outcomes;
requirements are tracked pass/fail/not-run per the Milestone 1 spec. Intentions
live in the spec, not here.

| ID | Status | Evidence |
| --- | --- | --- |
| M1-01 | partial | Base image slice verified (below): canonical Dockerfile, pinned inputs, non-root, offline startup. Selected toolchain/agent layers remain (`WGHQ2GW`). |
| M1-02 | not run | Mount planning pending (`JP73P2D`). |
| M1-03 | not run | Ownership/artifact separation pending (`KSCDG1J`). |
| M1-04 | partial | Identity helper verified with 16/16 tests on 2026-09-09 ([identity](../identity/README.md)); container-resource usage pending. |
| M1-05 | not run | Worktree mount planning pending (`JP73P2D`). |
| M1-06 | not run | Lifecycle/persistence proof pending (`24GJSHY`). |
| M1-07 | not run | Blocked on the human agent decision (`TG7VZBV`). |
| M1-08 | not run | Cache clearing pending (`HE2GM6N`). |
| M1-09 | partial | Failed-download behavior verified for the image build (below); other failure classes pending. |

## Base image — 61Q7E8F, 2026-09-09

Host: macOS 25.6.0 arm64, Docker server 29.5.2 (linux/aarch64), docker CLI
29.8.0.

- **Base image:** `debian:bookworm-slim` pinned by OCI index digest
  `sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171`
  (digest from `docker pull`/RepoDigests; linux/arm64 manifest digest
  `sha256:6bd27d44e6c32a66bbd72d7cb2b76a8ae3497ec2e5274a81abd1b37f6013fa1f`
  from `docker manifest inspect`).
- **mise:** `v2026.9.4` (latest release, published 2026-09-09). The release
  publishes no standalone checksum assets, so the pinned sha256
  `18303fdb59095acf0c50b0d23819b87182516988f9eb2ec016b52f8814916904` is the
  GitHub release-API asset digest (served over TLS, computed by GitHub). The
  tarball was downloaded on-host and matched that digest before pinning, and
  the build re-verifies it with `sha256sum --strict --check`. Stronger SLSA
  attestation verification exists upstream and remains an open choice.
- **Build:** cold `--no-cache` build 13 s; cached rebuild 0.6 s. Image
  `sha256:caca07509a9296b332fda830fa5b76966ef7279cbc2a076316ada920130b43b3`,
  `linux/arm64`, 145,774,378 bytes, default user `dev` (uid 1000).
- **Offline startup:** `docker run --rm --network none` printed uid 1000,
  mise `2026.9.4 linux-arm64`, git `2.39.5`, curl `7.88.1`, wrote and removed
  a file in `/home/dev` — a shell starts and reports tools with no network and
  no downloads. Warm container start 128 ms.
- **Failed build safety:** a build against the same tag with a wrong
  `MISE_SHA256` failed at the checksum step; the existing image ID was
  unchanged and the source tree had no modifications (only the new, untracked
  Dockerfile).
- **Exclusions by construction:** no GUI, no agent supervisor, no host Docker
  socket, no credentials or login state.

Only `linux/arm64` is exercised; no multi-arch or Windows support is claimed.
