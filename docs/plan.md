Working document for discussing and developing a game inspired by Stack Attack for Android and Web. First we define the game we want and the technical choices, then test the first playable milestone and use what we learn to plan further development.

**Current status.** The base game was accepted earlier. The November 19 release adds the agreed iron crates, traps, watchmaker’s cap, hunting boots, engineer’s goggles, slingshot and claw repairs. The [game rules](prototype.md) describe that release. The original plan and its decision log follow.

# Decisions so far

- Android and Web are both supported platforms. The Web version is a full game in its own right.

- The stack is Godot 4 stable + GDScript. The current target is Godot 4.7.2 stable with export templates 4.7.2.stable. `.godot-version` pins the exact build.

- The initial GitHub repository will be private. We’ll start preparing it once we agree on the basics.

- The private repository and published cloud environment are ready. The first technical milestone has separate approval.

- Record decisions, open questions and discussion progress here. Proposals need discussion before acceptance.

# Discussion stages

| Stage | Status | Intended outcome |
| --- | --- | --- |
| 1. Game concept | Fundamentals agreed | A story-free arcade game with one character and its own pixel art, with Braid and Dead Cells as visual references |
| 2. Stack and development process | Fundamentals agreed | Godot 4.7.2 + GDScript, Android and Web. The technical APK passed its phone test. The new prototype and its art still await acceptance. |
| 3. Controls and screens | Fundamentals agreed | Buttons and keyboard, two layouts, playfield, pause, game over, main menu, statistics and settings |
| 4. Game loop | Core rules agreed | Falling and moving crates, bottom-row clears, scoring and two loss conditions. Clarify remaining cases and tune the numbers in the prototype. |
| 5. First prototype | Scope agreed | All the core mechanics and screens discussed for Android and Web. Readiness criteria are listed below. |
| 6. Implementation plan | Sequence agreed | Work in testable increments. Refine the next steps after playtesting and feedback. |

# 1. Game concept

**Agreed vision.** A modern arcade game based on Stack Attack’s mechanics, with its own visual style.

- **References.** We studied versions of Stack Attack for their mechanics. We can define our own rules without choosing a single Siemens edition.

- **Core idea.** The player moves falling crates into a horizontal line at the bottom. A full bottom row disappears regardless of crate color, and the crates and character above it settle smoothly by one row. The first milestone excludes breaking crates. Jumping remains a movement option.

- **Initial scope.** Start with the core mechanics and one character. Additional mechanics, characters and abilities, such as moving two crates, are possibilities for later.

- **First milestone.** A pure arcade game with two claws, a constant speed and independent pauses between passes. Story can be revisited later. Puzzle levels with new mechanics are a future possibility outside the first prototype. Playtest the speed and range of pause lengths.

- **Art direction.** Pixel art with the atmosphere of Braid and Dead Cells as an additional visual reference. Create an original style and world without copying either game. Visual references to Siemens are optional. We chose pixel art over a painterly approach. **Technical goal.** Smoother play and a high frame rate. The target FPS is still open.

**First milestone boundary.** A basic arcade game with one character and two claws moving in opposite directions. The core rules are agreed. The game loop section lists the remaining cases. We’ll tune the numbers in the prototype. Puzzle levels, new mechanics and abilities remain ideas for later.

## Survey of Stack Attack versions

These findings describe the reference games. Our own feature choices follow the survey.

- **Classic version.** Crates fall and can be moved into lines that disappear. [Cybersport overview](https://www.cybersport.ru/tags/games/10-igr-dlya-knopochnykh-telefonov-v-kotorye-vse-zalipali-v-detstve).

- **Color 2D version with abilities.** The same [overview](https://www.cybersport.ru/tags/games/10-igr-dlya-knopochnykh-telefonov-v-kotorye-vse-zalipali-v-detstve) mentions it. The edition name is unconfirmed.

- **Stack Attack Advanced.** The [Siemens C65 review](https://mobile-review.com/review/siemens-c65.shtml) describes the isometric view, and the [uVeJuegos listing](https://uvejuegos.com/juego/Stack-Attack-Advanced-Mov/Mov/17143) mentions color combinations.

- **Stack Attack 2.** The [game listing](https://java2phone.ru/games3/170) describes alternative combinations and bonuses.

**Outcome.** For our game we chose smooth crate movement and a full horizontal bottom row that clears regardless of color. Isometric graphics, color combinations, bonuses and special abilities are outside the first prototype. The game loop section gives the detailed rules.

# 2. Stack and development process

**Agreed stack.** Godot 4 stable + GDScript for Android and Web. The current target is Godot 4.7.2 stable with matching export templates 4.7.2.stable so that local and cloud builds use the same tools. The upgrade from 4.6.3 was agreed on November 14, 2026, to allow editor installation through Homebrew and quick local Web checks. A separate agent is updating the published cloud environment.

**Cloud development.** Run headless checks for game logic and builds. Check appearance and controls separately on devices and in the browser. Graphical startup in the cloud environment still needs verification.

**First technical step after planning.** Prepare a minimal project with a test and build checks for both platforms. Compatibility is the initial renderer recommendation. Verify the required graphics effects on Android and Web before relying on them.

# 3. Controls and screens

**Controls to test.** Use simple on-screen buttons for “влево” (left), “вправо” (right) and “прыжок” (jump) in place of gestures. On Web and on Android with a keyboard connected, also support the left/right arrow keys to move and Space to jump, keeping touch buttons available. Start by pushing crates when the player moves into them and test this in the prototype. **Adaptive layout.** Support portrait with controls at the bottom and landscape with controls at the sides. Test comfort at different screen sizes separately. We agreed on the core screens and transitions using the layouts discussed. Visual mockups are still to come. The chosen style is pixel art with the atmosphere of Braid and Dead Cells as an additional reference. The game will have its own world and style, without copying either reference or requiring Siemens motifs. Choose the palette and specific visual details later, while continuing to test the controls on their own merits.

**Minimum game HUD.** Show the score and a pause button. The claws moving above the field give the player a cue before each drop.

**Pause menu.** Resume the current game, start over or return to the main menu.

**Main menu.** “Играть” (Play), “Рекорды” (High Scores) and “Настройки” (Settings).

**Settings.** Separate volume controls for music and sound effects. Android has optional vibration. Web hides the vibration toggle. The events that trigger vibration have yet to be approved.

**Statistics.** A separate local statistics screen shows totals and completed match history. Open it from the main menu. Old high scores retain their known dates and scores. See the [counting rules](prototype.md#saving).

**Game over screen.** Show the final score and the buttons “Играть снова” (Play Again) and “Главное меню” (Main Menu).

**Stage outcome.** A clear interaction flow and an agreed set of screens.

# 4. Game loop

Two claws travel toward each other on rails above the field at a constant speed. Each carries one crate, drops it over the chosen column and moves off the edge. After an independently randomized pause within the specified range, each claw returns to the start of its route with a new crate.

The player moves crates to fill the bottom row, which disappears regardless of color. Crates fall and move smoothly, staying upright without rotating or tipping. Their horizontal positions should be clear to the player. Visual polish can come later.

The character can move a falling crate on contact. An unsupported crate falls, so pushing a lower crate out from under an upper one can drop it onto the character and kill them.

When the bottom row disappears, the crates and character above it fall together by one row. If the new bottom row is full, it clears next. A chain of clears could trigger a visual cue such as “Вау!” (“Wow!”). The exact wording and any score multiplier have yet to be approved.

The first milestone excludes breaking crates and retains jumping for movement. In the first version the character has one life. A crate falling onto the character ends the game. The other loss condition is warehouse overflow, when at least one stack reaches the full height of the field. Check for overflow once a crate is resting on the stack at the top boundary.

Award points for lines cleared, with no time-based points. Consecutive clears are allowed and may be marked visually as a combo. A score multiplier has yet to be approved. Playtest points per line, claw speed and pauses. Use the prototype to tune fall and movement speeds, collision parameters and the feel of the controls. The game uses custom fixed-step AABB physics in GDScript.

## Research notes on the original rules (draft)

These notes come from descriptions and a reconstruction of the original game. The prototype has its own agreed rules.

- Descriptions mention cranes that drop crates, walking, pushing one crate and jumping. They also describe jumping to break a falling crate. See the [Cybersport overview](https://www.cybersport.ru/tags/games/10-igr-dlya-knopochnykh-telefonov-v-kotorye-vse-zalipali-v-detstve) and the [stktk reconstruction](https://github.com/eaun01re/stktk).

- The [stktk reconstruction](https://github.com/eaun01re/stktk) describes clearing a full bottom row, crates settling and the addition of cranes. It is a secondary, incomplete account of the original.

- The exact number of lives and scoring formula remain unconfirmed. The A50/A52 manuals give little detail about the game. The [A50 manual page](https://manualsdump.com/en/manuals/siemens-a50/222049/41) leaves these questions open.

**Rules status.** The decisions at the start of this section govern our game. Playtest speed, the pause range and controls. See the [prototype playtest parameters](prototype.md#playtest-parameters) for current values.

**Clarification of the earlier row diagram.** If a stable field has no gaps under crates, a full upper row implies that every row below it is full. This resolves the earlier question “нижний или любой ряд” (“bottom row or any row”). Our game already specifies that unsupported crates fall and that the bottom row clears.

**Next step.** Finish the first technical milestone, including a phone test of the APK, then move on to the next agreed work item. Planning can proceed while the numbers and technical details are open. Set initial values during implementation and test them in play.

# 5. First prototype

Ilya considers the full set discussed suitable for the first milestone. The goal is a complete, playable arcade game on Android and Web for assessing how enjoyable the controls are, how clearly the physics read and how the drops are paced. The scope and work sequence were agreed on November 11, 2026. After verification of the technical foundation, the full first prototype was authorized as one draft PR.

## First milestone scope

- **Gameplay.** One character, movement and jumping, and pushing crates, including falling crates on contact. Crates stay upright without rotating, fall smoothly when unsupported and can endanger the player when an upper crate falls.

- **Rules.** The bottom row clears and the crates and character above it settle. Consecutive clears may have a visual cue. The player has one life. Death or a stack reaching the full field height ends the game.

- **Pace and scoring.** Each claw delivers up to one crate per pass, at a constant speed with independent pauses. Award points for lines with no chain multiplier.

- **Platforms and input.** Android and Web are both full versions with on-screen buttons and keyboard support. Portrait places the buttons at the bottom and landscape places them at the sides.

- **Screens.** Main menu, game with score and pause, pause menu with three actions, results with restart or exit, local statistics and settings.

- **Settings and feedback.** Separate volume controls for music and effects. Android vibration can be disabled. Web omits the toggle. Choose specific sounds, vibration events and the chain message separately.

- **Art direction.** Original colorful pixel art with the atmosphere of Braid and Dead Cells as a reference. This direction is part of the project. The degree of art polish for the first milestone still requires agreement.

Story, puzzle levels, new characters and abilities, crate breaking, accounts and online leaderboards are outside the first milestone.

## Temporary art

Simple placeholder images were proposed for early mechanics testing. Ilya has not specifically approved this approach. If we use placeholders, label the builds as technical tests and keep the agreed pixel art in the plan.

## Proposed readiness criteria

- A single pinned project revision produces a runnable Android APK and working Web build.

- On both platforms the player can complete the full cycle from menu to game, pause or game over, then restart or return to the menu.

- Tests reproduce midair pushing, unsupported falls, a dangerous upper crate falling, a row clearing and settling, and a chain of clears. Crates remain upright and outcomes are independent of rendering frame rate.

- Each loss condition ends the game exactly once. The score matches the lines cleared. The order of collision processing must allow the character and crates to settle together safely after a normal clear.

- Two claws move toward each other at a constant speed, drop one crate per pass and return independently. The jaws visibly open, and there are no noticeable jumps when the claws meet or leave the field.

- Buttons and keyboard work. The field, score and menus are accessible in both layouts without controls overlapping them.

- Statistics and settings persist locally across application launches or page reloads in normal browser mode. Android and Web saves are independent. Browser storage limitations are documented.

- Volume changes are verified with audible sound. Android vibration can be disabled, and Web omits its toggle.

- Automated rule checks pass. Ilya tests control and smoothness on a phone and in a browser. Fix any bugs found or explicitly document and agree on them as limitations.

- Ilya reviews the first milestone’s appearance separately. If temporary art remains, identify it as such until the art is accepted.

After playtesting, record impressions, bugs and parameter changes. Keep field size, speeds, pause range and point values configurable. Test overflow, safe drops and repeated claw passes.

# 6. Implementation plan

## Proposed sequence for the first milestone

The original plan called for separate PRs. On November 11, 2026, Ilya authorized preparing the entire prototype in one new draft PR. Follow-up changes after his playtests can be released separately. The seven items below organize the work and its checks. They can all go in the agreed PR.

1. **Project foundation and two builds.** Pin Godot and the export templates. Prepare a minimal scene, a simple automated test and cloud environment instructions. Verify that the APK launches on a phone, the Web build opens in a browser and the test passes. This milestone is a technical build only.

2. **Playfield, character and input.** Implement movement, jumping, keyboard and on-screen buttons, and both layouts. Verify that the character is controllable on both platforms and that elements do not overlap. Test graphical startup in the cloud and the chosen renderer here.

3. **Crates and physical interactions.** Implement smooth falling, pushing, contact in midair, loss of support and the danger from an upper crate. Verify each case with a separate reproducible scene and check that rendering speed has no effect on the rules.

4. **Complete arcade game.** Implement row clearing and settling, chains, scoring, both loss conditions and two claws with constant speed and independent pauses. Play through a complete game and run automated rule scenarios.

5. **Menus and local data.** Implement the main menu, pause, restart, results, high scores, settings and saving. Verify all agreed transitions and persistence after relaunch. Test the sound and vibration settings with actual feedback.

6. **Art and sound.** Prepare mockups of the original pixel art style, selected images, readable clear effects, sound and Android vibration. Ilya assesses appearance and clarity on Android and Web. Agree on further polish separately and identify any temporary assets. Mockups can be prepared in parallel with earlier work.

7. **End-to-end testing and balance.** Play on a phone and in the browser, test both layouts, tune parameters and fix bugs. Verify that the first milestone meets its criteria, document limitations and obtain Ilya’s confirmation that the foundation works and is worth developing further.

## After the first milestone

Use playtest results to refine the plan for art polish and further mechanics. Puzzle levels, characters and abilities will have their own discussions and work items. They are outside the current implementation.

**Status.** The first milestone plan is agreed. The repository and published cloud environment are ready. The technical foundation and its APK have passed their checks. The playable prototype is ready on a separate branch for a single draft PR. Ilya still needs to test it on a phone and review the art.

# Decision log

- **November 11, 2026.** We agreed on the discussion sequence and a single planning document. Ilya chose falling, movable crates and disappearing lines, initially with one character. The art direction is colorful modern 2D pixel art. Smoother performance is a goal, with the target FPS still open. Extensions and abilities are deferred. The survey of original versions is complete. Later decisions refined our game rules, which are collected in the game loop section.

- **November 11, 2026.** We adopted Godot 4 stable + GDScript and both Android and Web as game platforms. We’ll pin the engine and export template versions during environment setup. Alongside headless checks we’ll check graphics and controls on devices and in the browser. The first technical step after planning is a minimal project, a test and verification of both builds.

- **November 11, 2026.** Ilya considers the agreed mechanics, controls and screens suitable for the first milestone. Readiness criteria and an implementation sequence have been drafted. The proposal to use placeholder art has yet to receive separate approval.

After each discussion, update the relevant section and its status and briefly record the decision. If the decision changes, keep the reason for the change.

- **November 11, 2026.** After the environment was published, the first technical milestone was authorized on a separate branch and in a draft PR. Godot/templates 4.6.3 were pinned. The technical scene has no game mechanics and tests startup, orientations and input. Its temporary appearance does not constitute approval of the game art. Phone testing of the APK remains open.

- **November 11, 2026.** Ilya confirmed that the technical APK works on a phone and authorized the entire agreed prototype in one separate PR, without an automatic merge. Implementation covers only the agreed mechanics and screens. The initial numeric parameters, chosen vibration events and original pixel art and sound are documented in docs/prototype.md for playtesting.

- **November 14, 2026.** After testing the unified buttons, Ilya authorized merging PR #2. He authorized a separate draft PR for a visual prototype based on the workshop reference, using the existing game rules. See `docs/workshop-visual.md` for assets and verification.

- **November 14, 2026.** At Ilya’s request, the visual prototype keeps only wooden crate designs. New types will arrive with distinct mechanics after a separate decision.

- **November 14, 2026.** The upgrade to Godot/templates 4.7.2 was agreed. macOS system packages are installed via Homebrew and tracked in dotfiles. Playwright is isolated in the project’s uv environment. Web is tested locally and Android in the cloud. A separate prompt is being prepared for the cloud update. The local results leave the published environment update to be verified.

- **November 15, 2026.** We agreed on two claws on rails, routes in opposite directions, a drop in the selected column and independent pauses off the edge. Speed and the range of pause lengths are constant for this version.

- **November 19, 2026.** We agreed on two concept sheets and a workshop release with iron crates, a trap, expanded equipment and independent repairs for the two claws. Acceptance of this release requires a published Web build, verification of real controls in both orientations, a revision check of the public site and footage of the mechanics from the Web export. The APK continues to build as usual in GitHub Actions.
