---
name: Feature Request
about: Propose a new chaotic VIP mechanic, hazard, gala venue, or agent skill
title: "[FEAT] "
labels: enhancement
---

## Feature Summary
<!-- What gameplay mechanic or tooling improvement are you proposing? -->

## Multiplayer & Determinism Impact
- **Authoritative Owner:** Host (`peer_id == 1`)
- **Client Inputs Needed:** (e.g. clamped intent / voice RMS)
- **Physics / Bandwidth Considerations:**

## Acceptance Criteria
- [ ] Unit test added under `tests/unit/`
- [ ] Verified in headless 1 Host + 2 Clients smoke test (`make test-mp`)
- [ ] Passes `make verify-all` with `orphan_nodes == 0`
