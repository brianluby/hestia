# AWCEX5Z: temporary AWS handoff

Observed 2026-10-02 on macOS 27.0.1 arm64, Docker Engine 29.5.2
linux/aarch64, Compose 5.5.1. Implementation commit `6fb7977`;
`hestia-agent:2026-09-10` image ID
`sha256:9c7150a7fefd9b35463199896bc080ff37e64100ea0821332d651761b112b026`.

`KEEP_ARTIFACTS=1 /bin/bash tests/workspace-aws.test.sh` exited 0:
9 passed, 0 failed, no SKIP. Synthetic temporary keys verified host-env and
mock AWS CLI process-JSON handoff, actionable missing/provider-error paths,
trace suppression, value-free Docker arguments, clean generated Compose and
state/image/container configuration, separate unauthenticated attach, and
unauthenticated replacement container. Disposable containers/network/cache
were removed; synthetic receipts retained outside source at
`~/.cache/hestia-aws-tests/run-yNE0m3n9`.

`bash tests/workspace-agent.test.sh` also exited 0: 24 passed, 0 failed,
no SKIP, against the same image. This inspects the already delivered native
integration and provider overlay, writable atomic settings, missing-auth
failure, settings/database persistence and fixture-source preservation.

Real AWS authentication, agent-assisted changes and native session resume
were **not run**. Bounded prerequisite checks found no AWS CLI in PATH and
no exported access-key/session/region variables; only presence was checked.
To complete AWCEX5Z/XJVWF4K acceptance, supply a scoped temporary session and
region through the explicit helper and run the real fixture change and
recreation/resume journey. Environment plumbing and mocked profile export
do not prove profile authentication, credential refresh or inference.
