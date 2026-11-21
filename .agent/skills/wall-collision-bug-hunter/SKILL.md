---
name: wall-collision-bug-hunter
description: >-
  Automated wall-clipping, pillar-tunneling, and out-of-bounds regression detector.
  Drives Players, VIP, Guards, Assassins, and Projectiles into every solid wall,
  column, vendor booth, table, and locked gate to guarantee zero walk-through bugs.
---

# Wall Collision Bug Hunter (`wall-collision-bug-hunter`)

Use this skill whenever adding or modifying map geometry, walls, pillars, doors/gates, entity movement, or projectiles.

## 1. Non-Negotiable Collision Laws
1. **Single Source of Truth (`src/world/wall_collider_grid.gd`):** Every architectural wall, archway wing, marble column, banquet table, vendor counter, and locked laser gate MUST register its exact footprint in `WallColliderGrid` when spawned.
2. **Universal 60 Hz Resolution:** Every moving entity (`BodyguardPlayer`, `VipStateMachine`, `GuardNpc`, `AssassinNpc`) MUST resolve its new position through `wall_grid.resolve_position(position, entity_radius, gate_locked)` inside `_physics_process(delta)`.
3. **Projectile Solid Blocking:** Plasma and Cryo bolts MUST terminate immediately upon touching any solid wall or locked gate (`wall_grid.is_point_inside_solid(...)`).
4. **Zero Corner Tunneling:** `WallColliderGrid.resolve_position()` runs multi-iteration relaxation so diagonal movement into wall/pillar corners cannot leak through.

## 2. Automated Verification Gate
Run the automated wall-clipping bug hunter (automatically executed in `make test-unit`, `.githooks/pre-commit`, and `make verify-all`):

```bash
godot --headless --path . --script .agent/skills/wall-collision-bug-hunter/scripts/test_wall_collisions.gd
```

Fails immediately if ANY entity:
- Clips inside a wall, column, vendor booth, or banquet table,
- Tunnels past a locked Security Laser Gate,
- Escapes the arena perimeter bounds, or
- Fires a projectile through a solid dividing wall.
