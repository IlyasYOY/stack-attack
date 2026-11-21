# Workshop visual prototype

After accepting the base prototype in PR #2 (`c0937e19cf26655043f44fde32d3b31807d0a6f1`), Ilya authorized a separate draft PR to show the proposed art in the game. Ilya will review the result and decide whether to accept the art direction.

## Art reference and access

The art brief sets the palette, lighting and mechanic’s silhouette. The reference image is stored separately from the repository.

The reference provided a cool-toned factory with amber windows, a warm lamp, a wooden frame with metal corner brackets, a brass rail, a checkered teal playfield, solid-looking crates and a mechanic with goggles and a prominent red U-shaped magnet. The workbench, mug, blueprint and wrench are background scenery.

## What the prototype includes

- Ten original 48×48 wooden crate designs share one atlas. They vary in wood tone, plank and brace direction, knots and wear. Each has the same outline and four corner fasteners. A crate keeps its design when falling, being pushed or pulled, clearing and appearing in the demo. A claw passes its design to the load when it drops it. The internal `color` tag is independent of the design.
- The 32×48 mechanic has a cap with goggles, a large, recognizable head silhouette, a shirt, scarf and belt. The idle, walking, jumping and pushing poses use the same canvas with either rocket boots or ordinary shoes. The mechanic’s hands are free.
- The playfield has a frame with bolts, a warm-toned rail and cranes, and a lamp with an inexpensive translucent light cone. Factory beams, windows, gears and a workbench fill the background. The scene retains Compatibility/WebGL 2 and needs no new physical lighting, 3D or expensive post-processing.
- An original small-caps bitmap font supports Cyrillic and Latin. Compact buttons share small fasteners and metal borders, controls have cream-colored icons, and the score has its own small plaque. The menus retain their title and existing entries without subtitles, footers or scrolling. The live AI background remains.

The assets for this visual prototype can be reproduced with Pillow using `python3 scripts/generate_art.py` and `python3 scripts/generate_font.py`. The scripts draw them from project-defined primitives and matrices. They use no cutouts from the reference or assets from other games. The SVG icon is also original.

## Gameplay boundaries

This visual pass leaves `simulation.gd`, `tuning.gd`, `prototype.tres`, `demo.gd`, `profile.gd` and `sound.gd` as they were. It keeps the 10×11 field, collisions, speeds, drops, clears, losses, scoring, controls and saves. Touch targets keep their size and position. The new score display fits the font inside the plaque while preserving the score value.

The internal `application/config/name` stays “Stack Attack · Ночная смена” (“Stack Attack · Night Shift”) because it helps determine the `user://` directory. A regression test protects the profile namespace when the art changes. The visible main menu title remains Stack Attack.

Rocket boots follow the [prototype equipment rules](prototype.md#equipment). Exhaust appears only on the extra jump in midair. The debug Web fixture `hero_pose` accepts `boots: true` to compare the two variants. It reads the pose and direction from the current state.

Flipping the sprite preserves the full canvas. At a display size of 16×24 and an offset of (-1,-2), the torso axis stays at x=7 relative to the player. The cap and hands protrude slightly as a visual detail. The sprite uses the existing collision shape. The test tracks a colored point on the scarf because equipment changes the leg area and shifts the center of the opaque silhouette.

## Verification and preview

```bash
source /workspace/setup-stack/env.sh
bash scripts/check.sh
source /workspace/stack-attack-local/debug-signing/debug-signing.env
bash scripts/export.sh all
python3 scripts/check_web.py
python3 scripts/package_builds.py
python3 scripts/package_showcase.py
```

`uv run --locked --group web python scripts/check_web.py --crates-only` compares all ten designs pixel by pixel in the Web build, checks that a falling crate inherits the claw’s design and compares frames after changing the internal `color` tags.

The full Web suite includes `--workshop-only` and `--sprites-only`. It checks portrait, landscape and Fold layouts, the absence of a magnet at gameplay scale, poses in rocket boots and ordinary shoes, both directions at the same position, torso alignment, transparent margins, font coverage, menus and a normal game. Proximity to a real crate selects the pushing pose. In the game this only affects animation.

For Library, the chosen format is **one** small PNG sheet made from several actual frames, using the single-file fast path for files up to 50 MiB. This avoids batching separate images through the previously unavailable upload helper. The source PNGs are kept separately in `build/screenshots/`. Captions sit outside the game UI, and a detail from an actual frame is enlarged by an integer scale factor. The sheet is kept private. Report a successful save and the Library ID only after the tool confirms it.

The APK and Web archive is available through a [manual workflow run](../README.md#download-builds). CI uses a temporary debug signature for each run. Installing over a previous test may require uninstalling the old APK and its data. The agent’s checks do not cover a physical Android device, vibration strength, display cutouts or phone performance. The browser’s Fold check uses a viewport size. Ilya will judge the visual impact, character scale and detail.
