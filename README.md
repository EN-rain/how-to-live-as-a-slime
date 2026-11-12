# How to Live as a Slime

A high-performance 3D physics-driven anime jelly slime simulator developed with **Godot Engine 4.6 (Mobile Renderer)**.

Features real-time continuous collision detection (CCD), procedural jelly deformation, volume-conserving mitosis fission and merging, an edible physics prop ecosystem, a $7.2\text{ km}$ procedural continent, and a seamless subterranean Signed Distance Field (SDF) cave system.

---

## 🎮 Controls Quick Reference

### Locomotion & Actions
| Action | Key / Input | Description |
| :--- | :--- | :--- |
| **Move** | `W` `A` `S` `D` / Arrows | Move forward, backward, strafe left and right |
| **Sprint / Fast Crawl** | `Shift` | High-speed crawl mode ($10.0\text{ m/s}$) |
| **Poke Slime** | `Left Click` (on slime) | Raycast poke creating localized spring ripples and displacement |
| **Orbit Camera** | `Left Click + Drag` | Rotate camera around slime |
| **Zoom Camera** | `Mouse Wheel Up / Down`| Scale-adaptive zoom |
| **Split Follower Clone** | `E` | Undergo bilateral coupled mitosis to spawn a follower companion |
| **Split Roamer Clone** | `Q` | Mitosis to spawn an autonomous wandering companion |
| **Merge Clones** | `M` | Absorb nearby clones back into the main body, conserving volume |
| **Liquid Crawl** | `Z` | Flatten into liquid posture to slide through low passages |
| **Return to Menu** | `Escape` | Return to 2D Main Menu |

### Quality & Diagnostics
| Action | Key / Input | Description |
| :--- | :--- | :--- |
| **Quality Presets** | `F5` / `F6` / `F7` / `F8` | Low (`F5`), Medium (`F6`), High (`F7`), Ultra (`F8`) |
| **Cycle Quality** | `F10` | Cycle through quality presets |
| **Physics Overlay** | `F3` | Real-time framerate/physics percentiles and live 3D wireframe mesh |
| **Developer Mode** | `F4` or `` ` `` (Tilde) | Toggle Developer Mode |
| **Dev Fly** | `V` *(in Dev Mode)* | Free 3D flight (Rise: `Space`, Sink: `C` or `Ctrl`) |
| **Dev Noclip** | `N` *(in Dev Mode)* | Phase through terrain, cave walls, and obstacles |
| **Dev Speed Adjust** | `[` / `]` or `Alt + Wheel` | Step speed ($8$ to $420\text{ m/s}$) |

---

## 🧬 Core Mechanics

### 1. The Core Sphere Traversal Rule
Unlike traditional rigid-body or soft-body characters, the slime is governed by a **two-layer clearance envelope**:
* **Outer Jelly**: Soft, responsive deformable envelope ($R \approx 2.0\text{ m}$ at scale 1.0).
* **Inner Core Sphere**: Hard, invisible clearance core ($R = 0.36\text{ m}$, diameter $0.72\text{ m}$ at scale 1.0).

**The Rule**: As long as a tunnel, gate, or crevice is wider than the Core Sphere ($0.72\text{ m}$ at scale 1.0), the slime deforms laterally, elongates along flow, and sweeps through without sticking. If the gap is narrower than the Core Sphere, the slime is physically blocked.

### 2. Volume Conservation & Mitosis ($V \propto s^3$)
* Slime volume is conserved: $V = \frac{4}{3}\pi R_{\text{vol}}^3 s^3$.
* Pressing `E` or `Q` initiates a **bilateral coupled split**:
  * An S-curve volume transfer splits mass 50/50.
  * A procedural connecting hourglass neck forms in [`slime.gdshader`](file:///d:/slime/shaders/slime.gdshader).
  * Tension snaps at the pinch point with elastic recoil impulses.
* Pressing `M` absorbs nearby clones, transferring volume back to the leader and recycling inactive nodes through an internal pool.

### 3. Digestion Ecosystem
* Smaller props (cubes, cylinders, prisms) that are pushed by the slime enter the `STATE_EATING` state.
* The prop dissolves smoothly via 3D procedural noise in [`prop.gdshader`](file:///d:/slime/shaders/prop.gdshader).
* Mass and volume transfer to the slime upon complete consumption.

---

## 🗺️ World Architecture

* **Procedural Continent ([`terrain/terrain.gd`](file:///d:/slime/terrain/terrain.gd))**:
  * $7200\text{ m} \times 7200\text{ m}$ terrain with non-linear grid density focused around player spawn.
  * Multi-biome shader: meadow grass, beaches, layered mesas, rolling hills, and snow-capped alpine peaks.
  * MultiMesh vegetation scattering with individual trunk and boulder colliders.
* **Subterranean World Cave ([`terrain/cave_system.gd`](file:///d:/slime/terrain/cave_system.gd))**:
  * Pre-baked Signed Distance Field (SDF) mesh with seamless terrain integration.
  * Features the Twilight Mouth, Collapse Hall, sunbeam skylight shaft, pool basin, underground lake, and vault sanctum with the ancient door.
  * Dynamic atmospheric controller ([`cave_atmosphere.gd`](file:///d:/slime/scripts/cave_atmosphere.gd)) adjusts exposure, sun attenuation, fog, and cavern glow in real time.

---

## 🤖 For AI Coding Assistants

If you are an AI assistant (Antigravity, Claude, Cursor, Copilot), **read [`AGENTS.md`](file:///d:/slime/AGENTS.md) first**. It contains:
* The cardinal invariants and strict rules (e.g. single transform writer).
* The fast task-to-file routing matrix.
* CLI commands to run tests headlessly.
* Deep-dive documentation links under [`docs/architecture/`](file:///d:/slime/docs/architecture/).
