# How to Live as a Slime

A 3D Godot prototype: you are a tiny slime. Eat, grow, eat bigger things. Cute but dark, no win condition.

Built from [`how-to-live-as-a-slime-plan.md`](how-to-live-as-a-slime-plan.md) — all 8 prototype steps at low quality first.

## Run

1. Open the folder in **Godot 4.6** (Forward+).
2. Press **F5** (main scene is `res://scenes/main.tscn`).

## Controls

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Space | Jump |
| R | Restart |

## How it plays

- You can only eat things **smaller than you** (`size <= your size`). Hover the camera over an edible; the slime's eat `Area3D` swallows it on touch.
- Each meal adds nutrition. Size = `0.8 * (nutrition / 27)^0.4`, so early bugs grow you visibly and late tiers need houses and statues.
- Movement speed and jump scale with size; the camera pulls back as you grow.
- Two mobs: **villagers** and **birds**. Bigger than you → they chase and bite (shrinking you). Smaller than you → they flee. Either can be eaten once you outgrow them.
- Eat everything to end up with an empty, quiet map. The dark part is authored in the tone, not the story.

## Test

A headless smoke test boots the world and exercises eat → grow → dissolve → damage:

```sh
godot --headless --path . res://tests/smoke_test.tscn
```

Exit code 0 means every check passed. (With Godot 4.6 installed at any path, substitute that executable.)

## Project layout

```
project.godot                  Godot 4.6, Forward+, Jolt
scenes/
  main.tscn                    Main + Player instance + HUD + audio
  slime.tscn                   CharacterBody3D + body mesh + eat Area3D
  edible.tscn                  Area3D + mesh + collision (kind drives the look)
  mob.tscn                     CharacterBody3D + mesh + collision (kind drives the look)
scripts/
  main.gd                      World build, spawns, camera, shake, HUD, restart
  slime.gd                     Movement, squash & stretch, growth, eating
  edible.gd                    11 edible kinds, size gate, absorb/dissolve
  mob.gd                       Villager/bird state machine (wander/flee/chase)
  toon_material.gd             Cel-shaded material factory (+ outline next_pass)
  lighting_preset.gd           Vendored from godot-skill-quality (MIT)
shaders/
  slime.gdshader               Wobble + cel bands + jelly highlight
  toon.gdshader                Cel bands + dissolve
  outline.gdshader             Inverted-hull outline
assets/sounds/pop.wav          Procedurally generated eat pop
.agents/skills/                19 Godot 3D agent skills (see AGENTS.md)
```

## Prototype notes (deliberate shortcuts)

- **Mobs steer instead of using `NavigationAgent3D`** — the map is flat and hand-placed, so there is no navmesh to bake. `mob.gd` has the swap-in note.
- **Input actions are registered in code** (`main.gd`) rather than in `project.godot`, so they cannot desync from the scripts during the prototype.
- **No win screen, no menus, no saves** — per the prototype cut list.
- Edible/mob meshes are built at runtime from primitives; swap in real low-poly scenes when the loop is proven.

## Skills & licenses

- `.agents/skills/` bundles [awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) (Apache-2.0) and [godot-skill-quality](https://github.com/laurentvv/godot-skill-quality) (MIT).
- `scripts/lighting_preset.gd` and the shader recipes follow those skills; keep their attribution.

The game itself has no license yet.
