# omp startup and preference evidence

Date: 2026-10-02. Host: Darwin arm64; runtime: Colima/Docker linux/arm64.
Source baseline: Hestia `a8fecc3`; omp `18.1.16`, release SHA-256
`d8612389c7af3cf3b69609c9149bff3cf07dcb65774b231d9dc4966b176b9720`.

## First-run marker (06174H1)

- Explicit canonical build: `rtk docker build --target agent -t hestia-agent:06174h1 .`, exit 0.
  Built image: `sha256:5e150fac2f682cf8eecf99b6aa5ae65b3a70cb2266bfe4eb2d13cd620a07f316`.
- `rtk env HESTIA_AGENT_TEST_IMAGE=hestia-agent:06174h1 MISE_TRUSTED_CONFIG_PATHS="$HOME/.cache/hestia-agent-tests" bash tests/workspace-agent.test.sh`, exit 0, 30 passed / 0 failed.
  Fresh native config resolves `setupVersion=2` and `theme.dark=titanium`;
  native `omp config set theme.dark dark-nord` works and is not shadowed.
  Policy bytes/ownership, attempted provider reenable, missing-auth failure,
  writable atomic settings replacement, recreation and unchanged source/Git pass.
- A generated workspace with a new empty `omp` state bind was started via
  the normal lifecycle helper (container
  `fc8a6fb092bc4d04d1ebbba31119f073f6963cf27863d7739ed990cd53f4e814`).
  Its network was disconnected, then `rtk docker exec -it` attached omp with
  synthetic AWS values. It reached the Bedrock status band and input composer
  with no onboarding prompts and visibly accepted a
  `HESTIA_FRESH_ATTACH_READY` draft without submitting it. Ctrl-C cleared
  the draft and Ctrl-D exited cleanly (exit 0).
  Explicit `omp setup` in the same image showed `Setup step 1 of 5` and
  `Set up your providers`, a positive control for the terminal probe.
  No inference request or real authentication was performed; no raw session
  or terminal capture is stored as evidence.

The image marker and upstream wizard gate are verified. Real AWS inference,
agent-assisted changes and native authenticated resume remain separate
`XJVWF4K` acceptance. No Argus or Windows support is established here.
