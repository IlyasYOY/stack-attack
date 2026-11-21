# Update the Stack Attack cloud environment to Godot 4.7.2

Configure the existing reusable cloud environment for `IlyasYOY/stack-attack` for Android and Web and verify the current playable prototype. Do the work on the cloud machine.

## Target version and starting point

- Use the standard Godot build without .NET. The exact output of `godot --version` must be `4.7.2.stable.official.ed1daf0bf`.
- Use `4.7.2.stable` export templates, including Android debug/release, single-threaded Web debug/release and the required engine data.
- Use the Compatibility renderer and a Web build without threads, GDExtension or PWA support.
- The last verified published snapshot was Debian 13.6 x86_64 with Godot 4.6.3. The repository is usually at `/workspace/stack-attack`, setup at `/workspace/setup-stack` and activation at `/workspace/setup-stack/env.sh`. Check the actual paths and state of the selected machine first.
- For setup, use the `main` branch of `IlyasYOY/stack-attack` with the project and CI updated to 4.7.2. Fetch the current revision and check `.godot-version` before running project checks.

The local editor was installed through Homebrew. Web testing runs on the Mac. The cloud environment is needed for Android builds among other tasks. Keep both platforms.

## 1. Check the environment and available revision

Read `AGENTS.md`, `README.md`, `docs/plan.md` and `docs/cloud-environment.md` in the available checkout. Check the environment and Git status and preserve any existing changes. Use the available cloud setup workflow so the installation persists beyond the current terminal session.

Compare `.godot-version` with the full target string above. If the updated revision is unavailable, prepare the 4.7.2 tools outside the checkout and verify their versions. Mark project tests as pending until the updated revision is available. Keep the old pin and strict version check in place. Full verification requires a checkout of the updated project.

## 2. Update the persistent toolchain

First back up the previous setup and environment files and check where the existing debug key is stored. Preserve the key, alias, password and private environment file without printing their values in chat or logs. Keep the key outside the checkout. Replacing it prevents installing an APK over the previous version.

For Linux x86_64, use the official `4.7.2-stable` release artifacts.

- `https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
- SHA-512: `9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65`
- `https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz`
- SHA-512: `ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079`

The official alternative template URL is `https://downloads.godotengine.org/?version=4.7.2&flavor=stable&slug=export_templates.tpz`. Verify the full SHA-512 checksum regardless of mirror. For another architecture, select the matching official binary and check it against `SHA512-SUMS.txt` from the same release.

Update the persistent setup scripts and `/workspace/setup-stack/env.sh` so that a new shell selects the target Godot via PATH or `GODOT_BIN`. On Linux, install the templates in `${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable`. Install `android_debug.apk`, `android_release.apk`, `web_nothreads_debug.zip`, `web_nothreads_release.zip`, `icudt_godot.dat` and `version.txt`.

Keep the existing JDK and Android SDK if they meet the requirements for this release.

- Java/JDK 17
- Android SDK Platform 36
- build-tools 36.1.0
- NDK 29.0.14206865. For the prebuilt APK without Gradle, neither NDK nor CMake compiles code.

Check the requirements in `https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/platform/android/java/app/config.gradle`. In `editor_settings-4.7.tres` set the actual paths to the Java SDK, Android SDK and existing debug keystore. Keep `export/android/shutdown_adb_on_exit = false`. Activation must set PATH, JAVA_HOME and ANDROID_HOME consistently.

Check `timeout`, `uv`, Python 3.13 and Chromium. Install Playwright and Pillow into the project’s `.venv` using the `web` group in `uv.lock`. Set `CHROMIUM_BIN` to the actual browser path if it differs from `/usr/bin/chromium` on Linux.

## 3. Verify the updated checkout

From the target revision in a new shell, run the following.

```bash
source /workspace/setup-stack/env.sh
cd /workspace/stack-attack
godot --version
uv sync --locked --group web --python python3.13
bash scripts/check.sh
bash scripts/export.sh web
uv run --locked --group web python scripts/check_web.py
```

Check the PASS result and `build/web-check.json`. The full browser test checks menus and sprites, keyboard, mouse and multitouch input, rotation, pause, restart, both loss conditions, a chain clear, persistence after reload and an actual audio signal. Inspect the screenshots and check for page and network request errors. The report must match the current PCK.

Then activate the existing private signing environment and run the Android export.

```bash
bash scripts/export.sh android
```

If there is no dedicated key yet, create one with the standard `scripts/create_debug_key.py` in a directory outside the checkout. Then activate the private environment file it creates. Preserve any existing keys. Keep shell tracing and verbose output off for signing commands.

Check `apksigner`, `aapt`, the arm64-v8a ABI, package `org.ilyasyoy.stackattack.techtest` and 16 KiB ZIP alignment. The APK still needs a phone test after its structure and signature pass. Run `package_builds.py` only when its clean-commit requirements are met. Do not create a commit solely for packaging.

## 4. Save the environment and test a fresh instance

Save the setup configuration and prepared environment using the method available in the setup chat. If Publish requires action from the owner, report the exact step. After publication, test a fresh instance launched from the published version. Check activation, the exact Godot version, the presence of templates and whether the checks pass again. If a fresh instance is unavailable, explicitly mark this check as outstanding.

In the final report, include the environment ID/revision if available, checkout revision, actual tool versions and paths, checks run and remaining limitations. Report the status of the current machine, published snapshot and fresh instance separately. Site publication, GitHub Releases, game rule changes, commits, merges and pushes are outside the scope of this setup task.

---

Posted by GPT-6 using Codex
