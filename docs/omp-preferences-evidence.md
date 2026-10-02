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

## Explicit appearance copying (WF6TXF9)

- `rtk env HESTIA_AGENT_TEST_IMAGE=hestia-agent:06174h1 bash tests/workspace-omp-preferences.test.sh`, exit 0, 12 passed / 0 failed.
- The test used synthetic host configuration containing six selected appearance
  leaves plus an excluded credential sentinel, an adjacent synthetic database,
  session and custom-provider file. Only selected appearance values reached
  workspace native settings; source SHA-256 stayed unchanged. Actual host
  preferences and credentials were never read.
- Existing native config stayed byte-identical on repeated import. Credential
  keys and structured values were rejected. Existing legacy database state
  prevented seeding. First-time import rejected a running workspace.
- The pinned native parser loaded the copied JSON mapping as YAML. Effective
  provider restrictions and first-run marker were preserved, native theme
  writes worked, and config bytes/theme survived a changed container ID.
- Independent read-only review identified a startup preservation race; the
  final helper requires a stopped workspace and rechecks all protected native
  paths before creation. Complete host/container agent writes before seeding.

This is an appearance-only, opt-in creation helper. It does not resolve custom
theme/extension files, model roles or custom-provider migration. Those require
separate explicit choices. Source references: [read-only settings loader](https://github.com/can1357/oh-my-pi/blob/61b1b8aef634334eaf1412afd003a763e1d1b9c1/packages/coding-agent/src/config/settings.ts#L588-L595)
and [native settings format/precedence](https://github.com/can1357/oh-my-pi/blob/61b1b8aef634334eaf1412afd003a763e1d1b9c1/docs/settings.md).
