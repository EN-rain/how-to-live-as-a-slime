# How to Live as a Slime — Agent Guide

**What this is:** a 3D Godot game, cute but dark. You play a tiny slime; you eat, you grow, until you can eat the world. Open sandbox, no win condition — the world's reactions are the progression.

**Read this first:** [`how-to-live-as-a-slime-plan.md`](how-to-live-as-a-slime-plan.md) — concept, pillars, size tiers, build order, prototype scope, risks. Do not re-derive the design; follow the plan.

## Engine & project setup

- **Godot 4.6**, **Forward+** renderer, **Jolt Physics**, Windows D3D12 driver (`project.godot`).
- Renderer is Forward+: SSIL and SDFGI are available, but are **not** available on Mobile/Compatibility. Keep that in mind before suggesting renderer changes.
- `[dotnet] project/assembly_name="How to live as a slime"` is set, but **no C# code exists yet — default to GDScript** (all installed skills assume GDScript). Ask before introducing C#.
- Project root is this directory (`D:\how-to-live-as-a-slime`). `.godot/` is editor cache — never edit it by hand.
- This is **not currently a git repository**. Ask before running `git init` or making the first commit.
- Godot is **not on PATH**. Open the project in the Godot 4.6 editor and press F5/F6 to run. If `godot` is added to PATH later, `godot --headless --import` is a cheap sanity check that the project parses.
- There is **no test suite yet**, and no game code yet — the repo currently contains only the plan and the default icon.

## Agent skills installed in `.agents/skills/`

OpenCode reads `.agents/skills/` as a project compatibility source. Each skill is a directory with a `SKILL.md`. Load a skill with the `skill` tool **only when the task matches its description** — do not load them all at once.

### Godot 3D engine skills (from `gamedev-skills/awesome-gamedev-agent-skills`, Apache-2.0, @ `19d93f9`)

| Skill ID | Use when |
|---|---|
| `godot-3d-essentials` | 3D nodes, cameras, lighting, environment/post, GridMap, project setup |
| `godot-shaders` | Writing Godot shading language — `spatial` shaders for the toon/wobble look |
| `godot-physics` | Rigid/Area/Static bodies (2D+3D), collision layers, raycasts — eating triggers, `Area3D` |
| `godot-animation` | AnimationPlayer / AnimationTree / Tween — absorb/dissolve tweens, squash & stretch |
| `godot-gdscript` | GDScript language: typing, lifecycle, `@export`, signals, idioms |
| `godot-nodes-scenes` | Scene tree, composition, instancing, autoloads, PackedScene |
| `godot-signals-groups` | Event-driven design — eating events, size-tier changes, "world notices you" reactions |
| `godot-resources` | Custom Resource classes (`.tres`) — data-driven edible/mob definitions |
| `godot-audio` | AudioStreamPlayer, buses, sync — eating sounds, screams |

### Discipline skills (same source)

| Skill ID | Use when |
|---|---|
| `shader-programming` | Cross-engine shader concepts: vertex/fragment, UVs, common effects |
| `game-feel` | Juice: squash & stretch, screen shake, hit-stop, feedback tiers — core to "eating is the toy" |
| `camera-systems` | 3D orbit/first-person, follow, pull-back as the slime grows, shake hooks |
| `performance-optimization` | Frame budget, draw calls, pooling — matters at late tiers with big crowds |
| `game-ai` | NPC decision-making: FSMs, behavior trees, steering — mobs flee/fight |
| `physics-tuning` | Fixed timestep, mass/drag, stability — scale physics with size |

### Godot 3D rendering / visual-quality pack (from `laurentvv/godot-skill-quality`, MIT, @ `1771e83`)

Measured in Godot 4.7.2 Forward+; applicable to 4.4+ (AgX tone mapping appeared in 4.4).

| Skill ID | Use when |
|---|---|
| `godot-lighting-environment` | Flat/washed-out scenes, black shadows, blown highlights — sun → sky → AgX → SSAO/SSIL → SDFGI → depth fog, in that order. Ships `lighting_preset.gd` |
| `godot-vegetation-shaders` | Trees/foliage/grass: leaf canopy shader, wind shader, MultiMesh scatter, ground-mask builder. Ships shaders + Blender prep scripts |
| `godot-lights-camera-post` | Character lost in shade, raw final image, jagged edges — cull-masked fill light, FOV/DOF, MSAA/TAA, vignette/grain |
| `godot-render-performance` | "Looks great but runs at 50 fps" — GPU-time bench, shadow presets, measure-then-lower method |

Not installed (deliberately): the `awesome-gamedev-agent-skills` **router** (it expects the full skill set), 2D/Unity/etc. skills, and C# skills.

## Conventions from the plan (follow these)

- **Build order:** slime movement → eating → growth → toon look → content → mobs → juice → tone. Finish all 8 at low quality before polishing any one.
- **The slime:** `CharacterBody3D` + vertex-wobble `spatial` shader + squash & stretch. Get the feel right first.
- **Reusable scenes:** build `Edible` (Area3D trigger; size, nutrition, color) and `Mob` (state machine + `NavigationAgent3D`) **once**, reuse everywhere.
- **Placeholders:** primitives and free toon assets; no custom art until the loop works.
- **Map:** small, hand-placed. **No procedural generation.**
- **Scope:** 3 size tiers (bugs/critters/people), ~10–12 edibles, 2–3 enemy types for the prototype. Cut the rest for now.
- **Growth:** scale player, camera distance, speed, jump and physics together; add a size gate.
- **Darkness:** from the world's reactions and visual tone, not from story.

## Working agreement

- Work in this directory only.
- Ask before: changing `project.godot` renderer/physics settings, adding new plugins or asset packs, initializing git, or switching GDScript → C#.
- Keep scenes small and composable; prefer instancing `Edible`/`Mob` over hand-built duplicates.
- Every change should leave the project openable in the Godot 4.6 editor without errors.
- Licenses: installed skills are Apache-2.0 (`awesome-gamedev-agent-skills`) and MIT (`godot-skill-quality`). Keep their attribution intact.
