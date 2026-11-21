## Summary
<!-- Briefly describe what this PR implements or fixes and why. -->

## Related Skill(s) Consulted
- [ ] `ragdoll-physics-tuner`
- [ ] `multiplayer-netcode-guard`
- [ ] `headless-coop-playtester`
- [ ] `voice-lipsync-mock`
- [ ] `clip-telemetry-profiler`

## Verification Gate Checklist (`make verify-all`)
- [ ] `make security` passed (zero API keys, secrets, junk files, or >10 MB assets)
- [ ] `make check` passed (strict static GDScript typing + `multiplayer-netcode-guard`)
- [ ] `make test-unit` passed (VIP state machine, 300-tick ragdoll stability, voice lip-sync mock)
- [ ] `make test-mp` passed (1 Host + 2 Headless Clients localhost E2E smoke test)
- [ ] `make test-perf` passed (1,000-tick benchmark, P95/P99 within budget, `orphan_nodes == 0`)

## Determinism & Authority Checklist
- [ ] All physics/gameplay mutations run strictly in `_physics_process(delta: float)`
- [ ] Every impulse/force is guarded with `.is_finite()` and clamped
- [ ] All `@rpc("any_peer")` handlers validate `multiplayer.is_server()` and clamp inputs
