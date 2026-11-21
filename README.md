# Stack Attack

An original 2D arcade game built with **Godot 4.7.2 + GDScript** for Android and Web. Two crane claws travel along rails delivering crates. Jump, push wooden crates and fill the bottom row. The game includes local statistics, match history, settings, and original sprites and sounds.

Use the left and right arrow keys to move and Space or the up arrow to jump. Press E or tap the circular arrows to pick up or swap an item. F activates the head slot and G activates the hand slot. With either the keyboard or on-screen buttons, you can move, hold down the watchmaker’s cap control and fire the slingshot at the same time.

Each destroyed wooden crate has a 10% chance of dropping an item (any of the 12 items is equally likely) and a 3% chance of dropping a trap. Otherwise the crate is empty. Iron crates make up 10% of new loads. You can move them with Strong Arms, and they drop into the receiver when the bottom row is full. See the [game rules](docs/prototype.md) for equipment and collisions.

## Run the Web version from source

Run the commands from the repository root. On Linux and macOS you need the standard Godot 4.7.2 build (GDScript), Bash, Git, Make, GNU `timeout`, `curl`, `unzip`, `shasum`, Python 3.13 and `uv`. Compare the output of `godot --version` with [.godot-version](.godot-version). If your package manager offers a different version, get the editor from the [Godot 4.7.2 archive](https://godotengine.org/download/archive/4.7.2-stable/).

On macOS you can install the command-line tools with Homebrew.

```bash
brew install coreutils python@3.13 uv
export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
```

Set up the Python environment and Web templates, then start the game.

```bash
uv sync --locked --group web --python 3.13
bash scripts/install_web_templates.sh
make web
```

The script verifies the SHA-512 checksum of the official template archive. `make web` builds the game and opens `http://127.0.0.1:8765/`. Use a browser with WebGL 2 support. To choose another port, run `make web PORT=8766`. Press Ctrl+C to stop the server. Statistics and saves are tied to the address and port.

Run `godot --editor --path .` to work in the editor. Run `bash scripts/check.sh` to check imports, game rules and scene startup. Run the browser test separately.

```bash
bash scripts/export.sh web
uv run --locked --group web python scripts/check_web.py
```

The test looks for Chromium at `/usr/bin/chromium` on Linux and for Google Chrome on macOS. Set `CHROMIUM_BIN` to use a different installed browser.

## Build a test APK on Linux

Install JDK 17 with `keytool`, Android SDK Command-line Tools, Platform Tools, SDK Platform 36 and Build Tools 36.1.0. Install the full **export templates 4.7.2.stable** through Godot’s template manager. The script in the Web section extracts only the Web templates. This project builds the APK from a prebuilt template without Gradle.

Set `JAVA_HOME` and `ANDROID_HOME` and add `$JAVA_HOME/bin` to `PATH`. In Godot, open **Editor Settings → Export → Android** and set Java SDK Path and Android SDK Path. Prepare a test build key in a directory outside the repository.

```bash
python3 scripts/create_debug_key.py "$HOME/.local/share/stack-attack/debug-signing"
source "$HOME/.local/share/stack-attack/debug-signing/debug-signing.env"
bash scripts/export.sh android
```

If needed, select the keystore you created in the editor’s **Debug Keystore** field. The export command verifies the APK signature and alignment. It writes `build/android/stack-attack-prototype-debug.apk` for ARM64, Android API 24+. Updating a test installation requires the same key. Uninstalling an older build with a different signature also deletes its local data.

## Work in Cockpit

In a prepared Cockpit environment, run `source /workspace/setup-stack/env.sh` in each new shell to select Godot, the JDK, the Android SDK and Chromium. These tools and the existing debug signing directory live outside the checkout. After activation, switch to your checkout and use the same check and export commands. Outside Cockpit, set up the tools as described above.

## Download builds

On each PR and push to `main`, the `headless` job checks the game and exports it for Android and Web. A failed test or export fails the job.

To get a build archive, use an account with write access and select **Actions → Godot headless checks → Run workflow**. Choose `main` or another branch of this repository that contains the workflow. The CLI equivalent is `gh workflow run check.yml --ref main`. A manual run repeats the checks and exports for the selected revision, then packages and uploads the files. After a successful upload, the archive is available under **Artifacts** for 14 days. If the storage quota is exhausted, the upload step reports an error. To download, sign in to GitHub with read access to the repository. The archive contains the test APK, Web ZIP, commit ID, SHA-256 checksums and Android reports. CI creates a temporary key for each run.

Extract the Web ZIP and start a server from the directory containing `web/`. Then open the game in your browser.

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory web
```

The game is at `http://127.0.0.1:8765/`. You can read `GODOT_LICENSE.txt` and `GODOT_COPYRIGHT.txt` alongside `index.html` through the same HTTP server. To package a clean commit locally, run `python3 scripts/package_builds.py` after `bash scripts/export.sh all` and the full browser check.

## Resources and licenses

- [Game rules and controls](docs/prototype.md)
- [Sprite, font and audio credits](docs/assets.md)
- [Godot license](notices/GODOT_LICENSE.txt) and [third-party notices](notices/GODOT_COPYRIGHT.txt). To read them in the APK, open it as a ZIP and look in `assets/notices/`.
- The project has yet to select a separate license for its code and game assets.
