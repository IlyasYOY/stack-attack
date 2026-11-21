# Stack Attack · Game rules

These rules apply to this version. The [project plan](plan.md) records when decisions were made.

## How to play

- Walk into a wooden crate to push it. Jump to get on top. You can also nudge a falling crate by touching it from the side.
- When the bottom row is full, an amber outline appears and the row drops into the dark receiver at the bottom of the workshop. The character and remaining crates then settle smoothly together by one cell. If the next bottom row is full, it clears too. Chain clears have no score multiplier.
- You have one life. The game ends if the warehouse overflows, a wooden crate hits you without protection, an iron crate hits you, you touch an open trap without hunting boots, or a repair mechanic falls on you while your head is unprotected.
- Unsupported crates fall. Pushing the bottom crate out of a stack can bring the top one down on your head. A helmet lets you break wooden crates on head contact.
- You earn no points for time survived. Two claws travel toward each other on rails. Each carries one crate, opens over the selected column, then goes off the edge. After its own random pause, it reappears with a new crate at the start of its route.
- **Claw overload.** At a random interval of 30–60 seconds of game time after the start or the end of the previous speedup, amber and blue sparks appear on the rails. After another 1.5 seconds, both claws double their speed for a random 8–12 seconds. Blue arcs and short trails show the speedup. Reflections on the gears and lamp and light in several windows brighten from the warning through the overload and fade with the sparks. When normal speed returns, the last sparks fade over half a second. Each claw’s offscreen wait also counts down twice as fast. On an open field the delivery rate roughly doubles.
- All phases and the spark pattern use the game clock `StackSimulation.elapsed` with a fixed 1/120-second step. The watchmaker’s cap slows this clock by half. Clearing a row or pausing the game stops it. Each new match picks a fresh first interval.

Use the left and right arrows to move, Space or the up arrow to jump, and Escape to pause or resume. On-screen buttons support simultaneous actions, including moving, holding the cap control and firing. The buttons sit below the field in both orientations. The field is always 10×11 cells. Rotating the screen changes the layout and releases any held touch buttons while preserving the match.

The main menu shows the title Stack Attack and the entries “Играть” (Play), “Статистика” (Statistics) and “Настройки” (Settings). Standard buttons on the main menu, pause, statistics, settings and results screens share the workshop theme, with a translucent dark background, a thin border and touch targets at least 48 logical units tall. The vibration toggle and pause button use the same theme. During a game, the score and pause button stay visible. From pause you can resume, start over or go back to the main menu. After a loss, the results screen shows the final score and offers a retry or a return to the menu.

Behind the main menu, settings and statistics, `StackDemo` runs a separate `StackSimulation` with the same parameters and rules and its own RNG, score and timers. After a short reaction delay the demo bot responds to visible falling crates and repair mechanics, chooses a clear escape route and stops approaching gear or stacks when there is danger. In quiet moments it uses the regular swap action to pick up suitable items and pushes a spare crate from a stack into an adjacent gap in the bottom row. Under threat it can hold the cap control, jump over a trap or dismantle one with goggles. With a slingshot it occasionally tries a shot. After a normal loss the next game starts in 1.2 seconds. The endless arcade game has no win condition. Clearing a row is a regular game event. The demo never saves results or changes the player’s own state. It stops during the player’s game, including pauses. Its music and effects use the same two volume settings, and the demo never triggers vibration.

The “Смена окончена” (Shift Over) screen shows the final score, with a font that fits the screen width. Match history shows the reason for the loss, rows cleared and other details.

## Equipment

Each destroyed wooden crate gives a single outcome, including during a row clear. There is a 10% chance of an item (each of the 12 is equally likely), a 3% chance of a folded trap and an 87% chance of an empty crate. A new item springs out fully charged, falls and bounces briefly. It falls again if it loses support.

Near an item, a circular-arrows button appears with its name and remaining charges. Press it or E to pick up the nearest item. If the slot is occupied, your equipped item takes the found item’s place, keeping its remaining charges. You can walk away or press again to swap back.

A wooden crate breaks if it falls on dropped equipment or is pushed into it from the side. A regular helmet or mallet on the ground spends one charge per hit and breaks on the last hit. Other dropped gear breaks one wooden crate and is destroyed with it. Strong Arms look like a dumbbell on the ground and muscular arms on the character.

- **Rocket boots** occupy the feet slot and have 10 charges. You can boost several times in one flight. Each separate jump press in midair spends one charge and fires the exhaust, even after walking off a ledge when the normal jump window has expired. Holding the button does not repeat the boost. At the very top boundary the charge is saved. After the last boost the boots disappear on landing.
- **Helmet.** The regular helmet occupies the head slot and has 5 charges. It breaks a crate that falls on your head or that you hit from below while jumping. A hit from below lets you continue rising. Each crate broken costs one charge, even for two hits in the same simulation step. The last charge breaks both the crate and the helmet. The next dangerous hit from above ends the match. Crates left unsupported fall. The score and the cleared-row and cleared-crate statistics change on row clears.
- **Work gloves** occupy the hand slot and have 6 charges. Hold the touch button next to jump or press and hold G to walk backward pulling an adjacent stable crate while facing it. To jump backward, keep pulling, press away from the crate and jump. If you jump or walk off a ledge, the crate finishes the step it started. Unsupported crates fall. On Web without touch input, item buttons are hidden. Equipment and key hints stay in the panel. Releasing the control, pausing or losing focus cancels the next step. A step in progress finishes if the path is clear. Only a full cell costs a charge. The gloves tear on the last cell, and crates above the support you moved fall.
- **Wooden mallet.** Picking it up replaces gloves in the hand slot. You can wear a helmet and boots with it. Its trial capacity is three charges. Each tap of the action button or press of G starts a short swing that hits one adjacent crate ahead. Holding does not repeat the hit, and a miss costs no charge. The final hit breaks the crate and then the mallet. Unsupported crates fall and the helmet protects you under the usual rules. The hit adds a broken crate to your statistics, leaving your score and cleared rows as they were. Pausing or losing focus cancels an unfinished swing.
- **Strong Arms** occupy the hand slot. Use the normal movement button to push two adjacent crates on the same level. Of the 6 charges, one moves a pair of wooden crates or one iron crate by one cell. A single wooden crate is still free to push. Trying to push a pair containing an iron crate or move into an obstacle costs no charge. Crates above fall when they lose support.
- **Speed boots** occupy the feet slot. Their trial range is 8 cells at ×1.55 speed, or 5.58 cells/s on an open field. By default you walk at normal speed. Hold the on-screen boot button or Shift while moving to speed up. Only the horizontal distance actually traveled at speed counts, including changes of direction. Standing still or pushing against an obstacle uses no range. Normal speed resumes after the last cell.
- **Lamp helmet.** This head-slot item reveals the drop columns of loaded claws when you press F or the lamp button. Its trial capacity is 4 activations of 1.5 seconds each. Using it without a suitable load is free. The first wooden crate to fall on your head breaks both the crate and the entire helmet, regardless of remaining lamp charges. The helmet still protects you when the lamp is out of charges.
- **Spring boots** occupy the feet slot. Their trial capacity is 8 charges. Hold jump while standing on a surface to add one power level every 0.18 seconds, as long as you have headroom and charges. Each level adds up to 2.4 cells/s to your initial vertical speed, capped by the height available from your position. Each level costs one charge, including a final level whose boost is limited by the ceiling. A gauge next to the icon shows the available levels from green to red. If a normal jump can already reach the ceiling, the jump is free. Release before the first level for a normal jump. When the boots reach the limit set by charges or height, they automatically launch you in a puff of steam. Pausing, losing focus or rotating the screen resets a charge-up in progress.

- **Watchmaker’s cap.** Hold F or the cap button to slow the character, crates, claws, repair mechanics, traps and receiver to half speed. This head-slot item has five real-time seconds of use across all activations. Release it to restore normal speed immediately. The slot shows the remaining time, which carries over when swapped. Pausing or losing focus releases the control. At zero the cap falls apart. A hit from above breaks the cap and ends the game.
- **Hunting boots** occupy the feet slot and automatically protect against two traps. The character is caught for 0.5 seconds of game time while crates continue to fall. The reinforced sole then forces the trap open and breaks it, spending one charge.
- **Engineer’s goggles** occupy the head slot. Press F or the goggles button to dismantle the nearest trap within one cell of your feet, including a folded trap. The goggles have three charges. Without a target you keep the charge. The goggles offer no protection against hits or triggering a trap.
- **Slingshot.** Each separate press of G or the slingshot button fires one of five pebbles from this hand-slot item. It targets a random visible repair mechanic first, including one riding a claw. Otherwise it targets a random visible working claw. Without a target you keep the pebble. The trajectory is visible from your hands to the selected target.

The field keeps its size and centerline in the menu, during a game and on the results screen. On a phone the equipment strip sits below the field, with head, hand and feet slots from left to right and a small animated character on the right. On a wide screen the gear sits to the right of the field, aligned with the corresponding body parts. A round swap button appears beside the slot for a found item, showing its image and remaining charges. Head, hand and feet slots stay visible when paused. A new run starts with no gear on the field or in the slots. The menu runs a separate demo that picks up equipment normally.

## Traps, iron crates and repairs

A trap drops folded. After landing, it moves and makes a warning sound before opening 0.8 seconds of game time later. If it lands during a row clear, the countdown starts when control returns. Touching an open trap with your feet triggers it, even if it opens under a stationary character. You can jump over it. A wooden or iron crate crushes a trap from above or the side and continues intact.

The three starting crates are wooden. Each new load has a 10% chance of being iron. You can see the material while the claw is carrying it. Iron crates fall and support objects above them. A hit to the head ends the game even with a helmet. Jumping into an iron crate from below stops your ascent. Strong Arms move iron one cell per charge. A normal push or work gloves cannot move it. The mallet rings on impact without spending a charge. Iron crushes loose gear and stays intact. A full bottom row removes iron crates and counts them as cleared. They contain no loot.

A pebble hitting a claw stops it with its current load. A repair mechanic approaches from the edge, gripping the underside of the rail with hands and feet. The mechanic spends 2.5 seconds of game time repairing the claw with a wrench, then climbs on top and rides off. The claw resumes its previous route with the same load. Each rail is repaired independently. A mechanic knocked off falls straight down. If repairs were unfinished, a new mechanic comes from the edge and starts over. Hitting a passenger leaves a working claw running.

A falling mechanic stops at the first collision. A wooden crate breaks with the normal chance of dropping loot. An iron crate stays intact. If the mechanic hits the character, a regular helmet spends a charge, a lamp helmet breaks, and without either protection the game ends and the cause is recorded in match history.

## Playtest parameters

Edit the `game/prototype.tres` resource in the Inspector. `game/tuning.gd` defines the initial values.

| Parameter | Starting value |
| --- | --- |
| Field | 10 columns × 11 rows |
| Character speed | 3.6 cells/s |
| Character jump speed / gravity | 8.8 cells/s / 24 cells/s² |
| Falling crates | Gravity 17, maximum speed 6 cells/s |
| Pushing | 3.1 cells/s, one crate moved one cell per push |
| Claw speed | 3 cells/s in opposite directions |
| Pause before returning | 0.35 to 1.10 s, independently for each pass |
| Time claws stay open after a drop | 0.23 s |
| Points per row | 100, no multipliers |
| Row highlight and removal / settling together | 0.22 / 0.25 s |
| Impact animation after the game stops | 0.42 s |
| Statistics | Local history of completed matches |

Three wooden crates start on the floor. If the drop column is blocked at the top of the field, the claw continues to the nearest free column on its route. If there are no free columns ahead, it leaves the field with its load. Both claws can release crates in the same simulation step in different columns. A released crate starts falling from the height it was carried at, without an initial push.

The game uses a custom AABB simulation with a 1/120-second step. An accumulator keeps the simulation independent of the rendering frame rate. During a clear, ordinary physics and claw movement pause so that settling together does not register a false hit on the character. Pausing or losing focus stops the game.

## Art and sound

The original pixel art workshop has factory silhouettes and amber windows, a hanging lamp, wood, brass and metal, ten wooden crate designs and a mechanic in a cap, goggles, shirt and scarf. Each crate keeps its design from the claw until it leaves the field. The wooden variants share the same properties. Iron crates keep their riveted shell in the claw and on the field. The project includes generators for workshop art and the font, `scripts/generate_art.py` and `scripts/generate_font.py`. The exported game is tested for Cyrillic and Latin coverage in its original bitmap font. See [workshop-visual.md](workshop-visual.md).

The character uses a fixed 32×48 canvas and has four poses. The scene draws it at 16×24 with offset (-1,-2) in the original 24 px per cell coordinate system. The torso axis stays at player.x+7, as in the previous 14×22 sprite. The cap and hands protrude slightly as a visual detail. Boots are drawn over the legs without changing collision dimensions. Flipping uses the whole canvas, including the transparent margins.

Music and effects were synthesized procedurally for this project without third-party recordings. The reproducible generator is `scripts/generate_audio.py`. The music is an original 16-second loop. Both platforms use PCM and streaming playback, with separate Music and Effects buses. On Android the music starts when the app opens. On Web the browser unlocks audio after the first user interaction. The two volume levels are saved independently. Android vibration fires on a jump, row clear or loss and can be disabled in settings. Web omits the toggle. On Android it reads “Виброотклик: Вкл/Выкл” (Vibration: On/Off). Enabling it saves the setting and requests a single 60 ms test pulse. Every control state explicitly uses the shared translucent button theme, so pressing, hovering or focusing retains that background. A phone is needed to judge how the hardware pulse feels. Ilya will assess the art and the feel of the controls.

Pushing or pulling produces a quiet scraping sound as long as the player is moving a crate. It plays continuously across adjacent cells and fades when blocked or released, even while the crate finishes its current step. Pausing or losing focus stops it. The background demo uses the same effect when pushing. Crate landings, helmet hits and gloves tearing each have their own sound.

## Saving

A game increments “Сыграно” (Played) once, when it ends in a loss. Returning to the menu, closing the game or restarting before a loss discards the unfinished match. History distinguishes warehouse overflow, a hit from a wooden crate, a hit from an iron crate, a trap and a falling repair mechanic.

Duration is measured in simulation steps from the start to the loss, including row-clear animations. For a hit, the record is created at the instant of collision. Pauses and the subsequent squashing animation are excluded from match duration. Cleared crates count those actually removed in bottom-row clears. Crates broken by worn or dropped equipment are counted separately. Best combo is the greatest number of consecutive rows cleared in one chain. History lists matches by completion time, newest first. Each card shows the local end date and time, duration, score, rows, crates, combo and cause of defeat. Tap to expand the details. Long histories are paginated.

`user://stack-attack-profile-v1.json` stores the three existing settings and the full history of new matches. Loading an old profile retains known dates and scores and includes its previous best score in the overall maximum. History marks old records. Unknown times, durations, clears and causes stay blank and are excluded from match aggregates. The number of broken crates is unknown for matches recorded before v3. The expanded set of loss causes can still read earlier history with “Придавило ящиком” (Crushed by a Crate) and “Склад переполнен” (Warehouse Full). The next save writes v3 to a temporary file and renames it. The loader checks for corrupt data.

On Web the profile is kept in IndexedDB for the game’s address and port. Browsers, addresses and Android installations have separate data. Private browsing, blocked storage or clearing site data can remove a save. The browser test waits for the write before reloading.

## Checks and delivery

```bash
source /workspace/setup-stack/env.sh
bash scripts/check.sh
source /workspace/stack-attack-local/debug-signing/debug-signing.env
bash scripts/export.sh all
python3 scripts/check_web.py
```

The headless suite checks movement, jumping, pushing and falling, loss of support, clears and chains, cap hold time, trap and iron interactions, shots, independent repairs and mechanic impacts, local data and screens. Eight reproducible games also check bounds and ensure crates never overlap. The suite compares 30 and 144 FPS and tests a long frame. An independent review led to eight targeted scenarios for diagonal and side contact. They cover movement in both directions, starting in contact or with a small vertical gap, and pushes already in progress at different speeds. At each of the 120 steps in each scenario, the test checks every pair of crates for overlap using their full rectangles, without the previous inset. The original case was reproduced in Godot before the fix. Each step rechecks the horizontal limit at the current height. A side impact stops the push command, and even a narrow area of actual contact provides vertical support. Crates can still fall clear of an obstacle and be pushed in midair.

`python3 scripts/check_web.py --game-over-only` tests both loss conditions with scores of 200/0 in portrait, landscape and at Fold size. It checks that only the heading and score appear as result details, that the model retains the cause and row count, and that touch, focus, restart and the main menu work without scrolling. It also checks the visible pixel center of scores 0/200/100000000, both buttons in their focused, hovered and pressed states, and readability over the actual moving demo using an explicit Web QA preview. In normal play the finished game remains in the background. Frames are saved to `build/screenshots/game-over-*.png`.

`uv run --locked --group web python scripts/check_web.py --ui-only` compares buttons on the main menu, pause, statistics, settings and results screens at 390×844, 844×390 and 768×1004. It checks the shared style, keyboard focus, touch target sizes, live demo and Android toggle through a Web debug scenario. The headless test also checks that enabling vibration requests a short pulse and that the demo never triggers it.

`uv run --locked --group web python scripts/check_web.py --statistics-only` tests match counting for two loss causes, pausing, restarting and exiting before a loss, v1 migration in IndexedDB, persistence after reload, and history order, details and pagination. Actual frames from the exported game are in `build/screenshots/statistics-*.png`. These checks are part of the full Web run.

`uv run --locked --group web python scripts/check_web.py --cranes-only` checks the claws passing each other, dropping loads, leaving the field and returning independently, plus pausing and rotating the screen in the actual Web export. Frames of the crossing and drop are in `build/screenshots/cranes-*.png`.

`uv run --locked --group web python scripts/check_web.py --animations-only` captures the highlight, receiver, settling and squash animation phases in the actual Web export. It checks pausing, layout changes, completion of chain clears and recording a loss. Frames are in `build/screenshots/animation-*.png`.

`python3 scripts/check_web.py --workshop-only` tests the new workshop visuals and captures real frames at 390×844, 844×390 and 768×1004. The character is visible empty-handed at gameplay scale, the field stays 10×11, the score, pause control and unequipped character are visible at the start of a run, and the demo is live. After a full run, `python3 scripts/package_showcase.py` makes one PNG sheet from real frames for saving to Library.

`python3 scripts/check_web.py --sprites-only` tests actual frames with the character facing either direction at the same position in portrait and landscape. It covers idle, stride, recovery, jump and push, with and without rocket boots. The test isolates a symmetrical strip on the torso, compares its center with the collision shape and across phases and equipment variants, and checks the fixed height, two distinct animation images and original transparent margins. The comparison PNGs use identical regions of actual screenshots enlarged by an integer factor of 4× without recentering. The full Web run includes this suite.

`uv run --locked --group web python scripts/check_web.py --loot-only` reproduces three items dropping from one row (seed 2), four helmet hits, picking up the helmet with one charge left and swapping using the keyboard and touch. It saves frames and a short video from the Web export in `build/screenshots/ground-*`. These are staged QA scenarios.

`uv run --locked --group web python scripts/check_web.py --boots-only` checks pickup, swapping, keyboard and touch jumps, the last charge and equipment reset on restart.

`uv run --locked --group web python scripts/check_web.py --helmet-only` tests hits from both directions, charge use on simultaneous contacts, falling after loss of support, the last charge and subsequent loss, using the helmet with boots, statistics and the HUD and pause layouts.

`uv run --locked --group web python scripts/check_web.py --gloves-only` tests continuous pulling while held, releasing individual fingers during multitouch, stopping after the current cell, obstacles, the last charge, falling crates, compatibility with other items and the button layout in portrait and landscape.

`uv run --locked --group web python scripts/check_web.py --mallet-only` checks picking up and swapping hand-slot items, keyboard and touch input without auto-repeat, misses, the final hit and the upper crate falling, statistics, pausing, losing focus and restarting. It captures portrait and landscape frames.

`uv run --locked --group web python scripts/check_web.py --bonuses-only` tests the new items in combination, when charges are spent or blocked actions are free, simultaneous touches, spring power levels, separate rocket boosts and input reset on focus loss and rotation.

Chromium tests the actual export over HTTP. The suite covers mouse, keyboard and touch, portrait and landscape, pause and resume, both restart paths, exit to menu, a chain clear, both losses, statistics and settings after reload, browser errors and an audio signal on each bus. The browser regression checks font and menu layout at nine sizes from 320×568 to 1004×768. Tab/Shift+Tab cycle through visible controls. Scrolling or swiping leaves panels in place. The report and frames are saved in `build/`. The diagnostic bridge is available only in debug exports with `?qa=1`. A normal launch shows the menu with a separate AI demo. “Играть” (Play) starts a new game for the player.

CI runs the headless suite and both builds on the exact PR head. A [manual run](../README.md#download-builds) also saves an Actions archive containing `stack-attack-prototype-debug.apk`, the Web ZIP, commit, SHA-256 checksums and Android check results. The archive excludes keys and is retained for 14 days. Downloading requires signing in to GitHub with access to the repository. The workflow does not create a public release.

Android targets API 24+, ARM64, package `org.ilyasyoy.stackattack.techtest`, versionCode 12 and versionName `0.3.1-workshop-prototype`. Each CI run gets a new temporary debug key, so installing over a previous test may require uninstalling the old APK and its local data. To install compatible local updates, retain a dedicated local key outside Git.

Ilya tests earlier builds on a phone and reports feedback. **The agent has yet to run this revision on physical Android or Fold hardware.** Real Android touch, vibration and sound, cutouts and system bars, mobile browsers and device performance need separate testing. SwiftShader and emulated touch do not cover those checks. Ilya’s playtests inform balance and visual presentation.

`uv run --locked --group web python scripts/check_web.py --overload-only` records the full overload cycle in the actual Web export. The QA scenario starts two seconds before the first warning. The video and a frame of the active phase are saved in `build/screenshots/crane-overload.*`.
