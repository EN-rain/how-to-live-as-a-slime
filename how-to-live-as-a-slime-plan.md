# How to Live as a Slime: Game Plan

**Engine:** Godot 3D
**Tone:** Cute but dark
**Structure:** Open sandbox, no goal. Just eat and grow.
**Art:** Stylized toon / cel-shaded
**Scope:** Small jam-style prototype first

---

## 1. Concept

You spawn as a tiny slime. The more you eat, the bigger you get. Keep growing until you can eat the whole world. Eating is the main content of the game.

## 2. Pillars

1. **Eating is the toy.** Every bite should feel juicy: squish, stretch, a satisfying sound and a visible dissolve.
2. **The world notices you.** With no win condition, the world's reactions are the progression.
3. **Scale is the spectacle.** The game should feel different at every size.

## 3. Core Loop

Eat, grow, unlock new things to eat, and face new things that fight back. Repeat.

## 4. Size Tiers

| Tier | You eat | What fights back |
|---|---|---|
| Tiny | bugs, berries, crumbs | spiders, birds, frogs |
| Small | critters, fruit, tools | dogs, cats, kids with sticks |
| Medium | livestock, people, carts | farmers, guards, wolves |
| Large | houses, trees, soldiers | knights, archers, mages, golems |
| Huge | towns, forests | heroes, siege weapons, dragons |
| Colossal | cities, mountains, oceans | armies, gods, world defenders |

Enemies are about your size or a bit bigger. As you outgrow a group, it switches from attacking to fleeing.

## 5. Growth Mechanics

- Each object has a nutrition value and a size. You can only eat things smaller than you.
- The camera pulls back as you grow. Speed, jump and physics scale with size.
- Eaten objects dissolve visibly inside your body.
- Your color can shift toward what you've eaten.
- Taking damage can shrink you, so growth can reverse.

## 6. Mobs and Enemies

- **Factions:** wildlife, villagers, military, magic users. Each reacts differently.
- **Threat meter:** the more you eat in an area, the more alarmed it gets, from fleeing to barricades to a summoned hero.
- **Behaviors:** flee, fight, trap, call for help. A few reusable state-machine behaviors cover many enemy types.
- **Weaknesses:** fire and salt hurt you, and large enemies have weak spots.

## 7. Cute but Dark

- **Cute:** round blob, huge eyes, bouncy sounds, pastel body.
- **Dark:** screams, abandoned homes, eyes that go blank at higher tiers, and a quiet ending when there's nothing left to eat.
- The darkness comes from the world's reactions and the visual tone, not from a story.

## 8. Godot 3D Technical Plan

- **Toon look:** a cel-shading spatial shader plus an outline (inverted hull or post-process).
- **Slime body:** a vertex-wobble shader on a mesh with a simple collider. Squash and stretch on movement and landing.
- **Growth:** scale the player, camera, speed and physics together. Add LOD and chunk streaming for late tiers.
- **Eating:** an Area3D trigger on the slime and a reusable `Edible` component (size, nutrition, color). Absorb with a tween and a dissolve shader.
- **AI:** a lightweight state machine plus `NavigationAgent3D`. Keep crowds cheap with LOD and simple movement.
- **Destruction:** pre-fractured meshes or a scripted "collapse into the slime" rather than real physics.

### Asset Strategy

**The slime: build it yourself (code and shader).**
A slime is a sphere with a wobble shader, a toon material and two eyes, so there is little to model. Owning it gives you:
- Squash and stretch, jiggle and absorb effects, because you control the vertices directly.
- Clean scaling from tiny to huge with no rig or topology problems.
- Color that changes based on what it ate.
- Full control over the feel of the main character.

Setup: an icosphere mesh (it wobbles more evenly than a UV sphere), a spatial shader for wobble and toon look, and eyes as separate small meshes.

**The world: use free models.**
Edibles, mobs, buildings and trees are where the content volume is, and modeling them all would eat the jam time. Sources:
- Kenney.nl (CC0, large low-poly packs)
- Quaternius (CC0, stylized low-poly characters, animals, nature)
- Poly Pizza and itch.io asset packs (check each license)

Rules:
- Prefer CC0 so there is no attribution to track.
- Pick one or two packs with a similar style instead of mixing many.
- Apply the toon material over all imported models so mismatched assets look consistent.
- Start with primitives (spheres, cubes) as placeholder edibles, then swap in real models once the loop is fun. The `Edible` scene makes the swap easy.

---

## 9. Prototype Scope (Jam-Style)

**Goal:** prove that eating and growing feels great.

| Keep | Cut for now |
|---|---|
| Wobbly toon slime | Full 6 tiers |
| Eat, grow, camera pulls back | Factions and threat meter |
| 3 tiers: bugs, critters, people | Heroes, bosses, dragons |
| About 10-12 edible types | City and planet scale |
| 2-3 enemy types that flee or bite | Chunk streaming, complex AI |
| One toon shader plus outline | Story, menus, save system |

## 10. Build Order

1. **Slime movement:** `CharacterBody3D` with a vertex-wobble shader and squash and stretch. Get the feel right first.
2. **Eating:** `Area3D` plus a reusable `Edible` scene. Absorb with a tween and dissolve.
3. **Growth:** scale player, camera distance, speed and jump together. Add a size gate.
4. **Toon look:** cel-shaded shader and outline. Do this early.
5. **Content:** about 10 edibles across 3 tiers, using primitives or simple low-poly shapes.
6. **Mobs:** basic state machine with wander, flee when you're bigger, attack when you're smaller. Start with 2 types, such as a bird and a villager.
7. **Juice:** sounds, eating particles, screen shake on big bites, a tiny "eaten" counter.
8. **Tone:** panicked screams, a blank-eyed slime at the top tier, an empty map after you eat everything.

## 11. Playtest Question

After 10 minutes of play, is chasing and eating things still satisfying? If yes, add tiers, factions and the threat meter. If not, fix the feel before adding content.

## 12. Tips for Small Scope

- Hard-code the slime (shader and mesh) and use free CC0 models for everything else. Don't model custom world art.
- Use primitives as placeholders until the loop works, then swap in the free models.
- Build the `Edible` and `Mob` scenes once and reuse them everywhere.
- Keep the map small and hand-placed. No procedural generation.
- Finish all 8 steps at low quality before polishing any one of them.

## 13. Risks

- The late-game scale jump is the hardest technical part, so prototype it early.
- Many enemy types means a lot of art. Use modular low-poly toon assets and reuse rigs.
- With no goal, check early that eating alone stays fun for 30+ minutes.

## 14. Milestones (After the Prototype)

1. **Vertical slice:** toon shader, 3 tiers, about 15 edibles, 3 enemy types.
2. **Content:** all tiers, threat meter, factions, heroes and bosses.
3. **Polish:** audio, particles, UI, the "world eaten" moment.
