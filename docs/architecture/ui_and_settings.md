# UI, Settings, Audio Synthesis & HUD

> **Context**: Deep technical architecture reference for [`autoload/settings_manager.gd`](file:///d:/slime/autoload/settings_manager.gd), [`scripts/hud.gd`](file:///d:/slime/scripts/hud.gd), [`main_menu/main_menu.gd`](file:///d:/slime/main_menu/main_menu.gd), and [`main_menu/core_rule_diagram_2d.gd`](file:///d:/slime/main_menu/core_rule_diagram_2d.gd).

---

## 1. System Overview

```
[SettingsManager (Autoload Singleton)]
   ├── Persistent Config (user://settings.cfg)
   ├── Global Quality Presets (F5-F8 / F10)
   ├── Procedural UI Sound Synthesizer (AudioStreamWAV generator)
   └── Rebindable Action Mapping & Conflict Resolution
         │
         ├──► [MainMenu (2D Menu Stage)]
         │      ├── Threaded Scene Loading (ResourceLoader)
         │      ├── Sliding Sheet Sub-menus (Guide, Settings, Credits)
         │      └── CoreRuleDiagram2D (Animated vector Core Sphere schematic)
         │
         └──► [SlimeHud (3D In-Game HUD)]
                ├── Floating Glass Pills (Stats, Hints, Dev status, Toasts)
                └── F3 Debug Overlay (Framerate percentiles & live 3D wireframe)
```

---

## 2. Settings Manager ([`settings_manager.gd`](file:///d:/slime/autoload/settings_manager.gd))

### Architecture & Persistence
* Saved to disk at `user://settings.cfg` using Godot's `ConfigFile`.
* Categories:
  * `display`: `window_mode`, `resolution_index`, `vsync`, `max_fps`, `ui_scale`.
  * `graphics`: `quality_preset` ($0-3$), `msaa` ($0-3$), `shadow_quality` ($0-3$), `grass_density` ($0.4-1.3$), `jiggle_strength` ($0.2-2.2$).
  * `audio`: `master_volume`, `music_volume`, `sfx_volume`, `ui_volume`, `mute_unfocused`.
  * `controls`: `mouse_sensitivity`, `invert_y`, `zoom_speed`.
  * `accessibility`: `reduce_motion`, `high_contrast`, `text_scale`.
  * `gameplay`: `night_mode`, `show_hud_hints`.

### Quality Presets Table
| Preset | Index | Hotkey | Shadows | Shadow Distance | Shadow Splits | MSAA | FXAA | Grass Density | Tree Dist | Rock Dist |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Low** | 0 | `F5` | Off | $30\text{ m}$ | Orthogonal | Disabled | Yes | $0.4\times$ | $260\text{ m}$ | $200\text{ m}$ |
| **Medium** | 1 | `F6` | On | $60\text{ m}$ | Orthogonal | Disabled | Yes | $0.7\times$ | $420\text{ m}$ | $340\text{ m}$ |
| **High** | 2 | `F7` | On | $120\text{ m}$ | 2 Splits | $2\times$ | No | $1.0\times$ | $550\text{ m}$ | $450\text{ m}$ |
| **Ultra** | 3 | `F8` | On | $200\text{ m}$ | 4 Splits | $4\times$ | No | $1.3\times$ | $750\text{ m}$ | $600\text{ m}$ |

* **Cycle Shortcut**: `F10` cycles presets.

### Procedural UI Audio Synthesizer
Rather than depending on external audio files, `SettingsManager` synthesizes clean, responsive audio wave streams programmatically on startup:
* **Sounds Generated**: `poke`, `click`, `swoosh`, `slider`, `splat`.
* **Technique**: Procedural frequency sweeps and envelopes written into 16-bit PCM raw byte buffers and wrapped in `AudioStreamWAV`.

---

## 3. In-Game HUD ([`hud.gd`](file:///d:/slime/scripts/hud.gd))

* **Pill Elements**:
  * Stats: Volume, scale, consumed prop count.
  * Hint Bar: Action shortcuts and commands.
  * Toast Notifications: Quality preset changes, state messages.
  * Dev Mode Banner: Active speed and noclip/fly indicators.
* **F3 Diagnostics & 3D Wireframe Overlay**:
  * Displays $p50$, $p95$, $p99$ millisecond frame times and physics process times.
  * Displays per-tick solver rates: `set_points`, `cast_motion`, `intersect_shape`, `get_rest_info`, `_bake_dims`, `_rebuild`.
  * Renders real-time 3D wireframe of every active slime's exact physical collision hull using an `ImmediateMesh` on top-level lines.

---

## 4. 2D Main Menu & Interactive Visuals

### [`main_menu.gd`](file:///d:/slime/main_menu/main_menu.gd)
* **Threaded Loader**:
  * Uses `ResourceLoader.load_threaded_request("res://scenes/main.tscn")`.
  * Polls progress via `load_threaded_get_status` with a minimum duration barrier ($0.3\text{ s}$) to prevent jarring single-frame flashes.
* **Sub-Menu Sheets**:
  * Slide-out glass cards for **Guide**, **Settings**, and **Credits**.
  * Input rebinding capture modal with conflict detection.

### [`core_rule_diagram_2d.gd`](file:///d:/slime/main_menu/core_rule_diagram_2d.gd)
* Vector canvas schematic demonstrating the **Core Sphere clearance rule**:
  * Interactive slider for gate gap width ($0.48\text{ m} - 2.40\text{ m}$).
  * Animated 2D slime traveling left to right.
  * When gap $\ge 0.72\text{ m}$: Outer jelly deforms and the body sweeps cleanly through with status text in gold.
  * When gap $< 0.72\text{ m}$: Slime compresses up to the inner glowing Core Sphere and stops with collision recoil in red.
