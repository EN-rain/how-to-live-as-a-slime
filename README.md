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
| Esc | Pause / Settings / Save Menu |
| F6 | Quick Save |
| F9 | Quick Load |

## How it plays

- You can only eat things **smaller than you** (`size <= your size`). Hover the camera over an edible; the slime's eat `Area3D` swallows it on touch.
- Each meal adds nutrition. Size = `0.8 * (nutrition / 27)^0.4`, so early bugs grow you visibly and late tiers need houses and statues.
- Movement speed and jump scale with size; the camera pulls back as you grow.
- Two mobs: **villagers** and **birds**. Bigger than you → they chase and bite (shrinking you). Smaller than you → they flee. Either can be eaten once you outgrow them. Grounded mobs use `NavigationAgent3D` and obstacle-avoidance feelers to navigate around trees and rocks.
- Two tone beats from the plan: past size **2.6** the pupils go pale, and once the map is empty the HUD reads **Nothing left to eat.** and opens the **World Eaten** summary overlay with your final size, time, and best record.
- Save or load your run anytime via **Esc** or **F6 / F9** (`user://slime_save.cfg`).

## Performance

Target: a locked 60 fps on integrated graphics. Measured on **Intel Iris Xe (D3D12, Forward+, 1152×648)** by running the game with `--disable-vsync --print-fps` and reading the reported FPS:

| Build | FPS |
|---|---|
| First pass (SDFGI + SSAO on, per-prop materials) | **12–17** |
| SDFGI off | 24–28 |
| SSAO off | **85** |
| + shared materials/meshes, instance-uniform dissolve, shadow & distance budgets | **~85–100** |

What produced most of it, in order of cost:

1. **SSAO off by default** (~55 fps on this GPU). Full-screen pass, and the toon bands plus sky ambient already separate forms. Toggle: `ssao_enabled` on `World` in the Inspector or in the in-game Settings menu.
2. **SDFGI off by default** (~10 fps). Toggle: `sdfgi_enabled` on `World` in the Inspector or in the in-game Settings menu.
3. **Shared materials and meshes.** `ToonMaterial.shared()` caches one material per kind/colour, and each edible kind builds and caches its mesh once instead of 66 times.
4. **Instance-uniform dissolve.** `toon.gdshader` declares `instance uniform float dissolve`, so the dissolve is set per mesh instance via `set_instance_shader_parameter` — one material stays shared across all props of a kind. (This also removed a runtime bug.)
5. **Shadow budget.** Two cascade splits over 55 m instead of four over 300 m; only props ≥ 1.5 m cast shadows.
6. **Distance culling.** Edibles cull at 32–75 m by size, mobs at 85 m, camera far plane 160 m.
7. **Icosphere slime body.** 642 evenly distributed vertices instead of a pole-pinched UV sphere: smoother wobble and less overdraw at top size.

Scaling up later: flip `ssao_enabled`/`sdfgi_enabled` on for a discrete GPU, then add real LOD tiers and chunk streaming (both cut from the prototype).

## Plan audit

Checked against `how-to-live-as-a-slime-plan.md` after the scene architecture & menus pass.

| Plan | Status | Notes |
|---|---|---|
| §2 Eating is the toy | Done | Squash, absorb tween, dissolve, pop, particles, shake |
| §2 The world notices you | Done | Mobs flee/bite; HUD reaction label & tier progress bar track world response |
| §2 Scale is the spectacle | Done | Size ×7 range, camera pull-back, speed/jump scaling |
| §4 Six size tiers | Partial | Prototype ships 3 (bugs → critters → villagers/buildings), per §9's cut list |
| §5 Nutrition + size gate | Done | `size <= your size`, growth curve documented in `slime.gd` |
| §5 Dissolve, colour shift, reversal | Done | Dissolve on eat; body colour drifts toward meals; bites shrink you |
| §6 Reusable mob state machine | Done | `wander` / `flee` / `chase`+bite shared by villager and bird |
| §7 Cute pastel blob, bouncy audio | Done | Pink-green jelly, procedural `pop.wav` |
| §7 Blank eyes at top tier | Done | `_update_eyes()` swaps pupils to pale at size ≥ 2.6 |
| §7 Quiet ending | Done | "Nothing left to eat." + World Eaten overlay once every edible and mob is gone |
| §8 Cel shader + outline | Done | `toon.gdshader` + `outline.gdshader` as `next_pass` |
| §8 Wobble + squash & stretch | Done | `slime.gdshader` vertex wobble, volume-preserving squash |
| §8 Area3D + reusable Edible | Done | One `Area3D` on the slime, one `edible.tscn` for all kinds |
| §8 Icosphere slime body | Done | `scripts/icosphere.gd`, eyes & materials authored in `slime.tscn` |
| §8 `NavigationAgent3D` | Done | `NavigationRegion3D` in `world.tscn` + `NavigationAgent3D` and obstacle feelers in `mob.tscn` |
| §8 LOD / chunk streaming | Partial | Distance culling + shadow budget; real LOD is post-prototype |
| §8 Scripted collapse instead of physics | Done | Absorb tween into the slime |
| §9 Prototype scope table | Done | 11 edibles, 2 mob types, 3 tiers, one toon shader |
| §10 Build order 1–8 | Done | Shipped in order, all at low quality first (§12) |

## Test

A headless smoke test boots the world and exercises eat → grow → dissolve → damage → save/load:

```sh
godot --headless --path . res://tests/smoke_test.tscn
```

Exit code 0 means every check passed. (With Godot 4.6 installed at any path, substitute that executable.)

## Project layout

```
project.godot                  Godot 4.6, Forward+, Jolt
scenes/
  main.tscn                    Main + World + Player + Camera3D + HUD + GameMenus + EatSound
  world.tscn                   WorldEnvironment + Sun + NavigationRegion3D + Ground + Walls + Trees + Rocks
  slime.tscn                   CharacterBody3D + Body mesh + LeftEye/RightEye & Pupils + EatArea
  edible.tscn                  Area3D + Mesh + Roof + Collision (EdibleData drives the look)
  mob.tscn                     CharacterBody3D + Mesh + Head/Wings/Eyes + Collision + NavigationAgent3D
  tree.tscn                    Reusable StaticBody3D tree obstacle
  rock.tscn                    Reusable StaticBody3D rock obstacle
  eat_burst.tscn               Reusable GPUParticles3D absorption burst
  ui/game_menus.tscn           Pause/Settings menu, Tier progress bar, Save toast, Win screen
scripts/
  main.gd                      Spawns, camera, shake, HUD, save/load wiring, exported scene/audio refs
  world.gd                     GameWorld: exported lighting, sun, fog, SSAO/SDFGI, palette & navmesh setup
  slime.gd                     Exported movement/growth/feel/look/node groups, squash, blank eyes
  edible.gd                    EdibleData-driven props, size gate, absorb/dissolve, mesh/shape cache
  mob.gd                       MobData-driven villager/bird FSM + NavigationAgent3D & obstacle feelers
  save_manager.gd              SaveManager: run state, world completion records & settings persistence
  ui/game_menus.gd             GameMenus: pause/settings UI, progression indicator, and win overlay
  data/edible_data.gd          EdibleData resource: id, shape, visual_scene, size, nutrition, colour
  data/mob_data.gd             MobData resource: size, speeds, flies, bite stats
  toon_material.gd             Cel-shaded material factory + `shared()` cache
  icosphere.gd                 Even-subdivision sphere for the slime body
  lighting_preset.gd           Vendored from godot-skill-quality (MIT)
resources/
  edibles/*.tres               11 edible kinds, editable in the Inspector
  mobs/*.tres                  villager, bird, editable in the Inspector
shaders/
  slime.gdshader               Wobble + cel bands + jelly highlight
  toon.gdshader                Cel bands + per-instance dissolve
  outline.gdshader             Inverted-hull outline
assets/sounds/pop.wav          Procedurally generated eat pop
tests/
  smoke_test.tscn              Headless boot + world/visuals/eat/grow/dissolve/input/save checks
  smoke_test.gd
.agents/skills/                19 Godot 3D agent skills (see AGENTS.md)
```

## Skills & licenses

- `.agents/skills/` bundles [awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) (Apache-2.0) and [godot-skill-quality](https://github.com/laurentvv/godot-skill-quality) (MIT).
- `scripts/lighting_preset.gd` and the shader recipes follow those skills; keep their attribution.

The game itself has no license yet.
