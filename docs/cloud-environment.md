# Cloud environment and prototype builds

The most recently verified published environment was tested on November 11, 2026, on Debian Linux 13.6 x86_64 with Godot 4.6.3. The current checkout uses **4.7.2** so the editor can be installed via Homebrew and the Web build tested locally. A separate agent is updating the published cloud snapshot using the [setup prompt](cloud-setup-prompt.md). That update still awaits verification.

The cloud setup scripts live outside the checkout in `/workspace/setup-stack`. After the update, sourcing `/workspace/setup-stack/env.sh` should select the exact build in `.godot-version`. The README covers local macOS setup. The project check and export commands neither install software nor accept licenses. A separate script, `install_web_templates.sh`, installs the Web templates.

## Pinned tools

| Component | Required version |
| --- | --- |
| Godot, standard build without .NET | 4.7.2.stable.official.ed1daf0bf |
| Export templates | 4.7.2.stable |
| JDK / javac | Temurin 17.0.21+9 / 17.0.21 |
| Android command-line tools | 19.0 |
| Android platform-tools | 37.0.1, build 15733141 |
| Android SDK Platform | API 36, revision 2 |
| Android build-tools | 36.1.0 |
| NDK | r29 / 29.0.14206865 |
| CMake | Package 3.10.2.4988404, executable 3.10.2 |
| Chromium / Python Playwright | 156.0.8078.79 / 1.62.0 |
| Pillow | 13.0.0 (assets and screenshot analysis) |

Godot and the new Web templates were installed locally on macOS on November 14, 2026. The other cloud tool versions in the table come from the November 11 check and must be verified again by the setup agent. Playwright and Pillow are pinned in the `web` group and `uv.lock`. Use Python 3.13 in the project’s `.venv`. On macOS the test uses the installed Chrome. In the cloud it uses `/usr/bin/chromium` or `CHROMIUM_BIN`.

Run `source /workspace/setup-stack/env.sh` in each new shell. Before activation, `java` selects the system Java 21 and `javac`, `adb` and `sdkmanager` are missing from PATH. Setting JAVA_HOME/ANDROID_HOME alone does not activate PATH.

Godot and its templates must match. `.godot-version` and `scripts/common.sh` enforce the exact engine build. On Linux the templates live in `${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable`. Transfer the Android settings to `editor_settings-4.7.tres`. Java SDK Path and Android SDK Path must point to an existing JDK and SDK. Verify 4.7 separately even if 4.6 is configured.

The Android configuration for release 4.7.2 still uses Java 17, SDK 36, build-tools 36.1.0 and NDK 29. The project pins the release-specific values for reproducibility instead of using `latest`. The standard APK uses a prebuilt template without Gradle. NDK/CMake do not compile code for this build.

## Repeat the checks

After activation, run the following from the checkout.

```bash
bash scripts/check.sh
python3 scripts/create_debug_key.py /workspace/stack-attack-local/debug-signing
source /workspace/stack-attack-local/debug-signing/debug-signing.env
bash scripts/export.sh all
uv sync --locked --group web --python python3.13
uv run --locked --group web python scripts/check_web.py
uv run --locked --group web python scripts/package_showcase.py
```

- `check.sh` imports the project, runs GDScript checks for game rules, screens, controls, local saves and orientation changes, then launches the game headless in a separate process. It also tests single-screen menu layouts at Fold sizes and with the Android vibration row. All elements must fit without a ScrollContainer. A timeout catches hangs, and the log check for ERROR catches import failures.
- `export.sh` produces a debug Web build and a signed debug APK. Android checks use apksigner, aapt and zipalign with 16 KiB page alignment. Passwords are passed through the official Godot environment variables and kept out of the export preset.
- `check_web.py` runs a temporary localhost HTTP server and Chromium with the SwiftShader software renderer. It tests mouse and keyboard input, simultaneous touches on the canvas, resizing, a full game, pause and both restart paths, both loss conditions, a chain clear, persistence after reload and actual audio output. Viewports are 1280×720, 720×1280, 390×844, 844×390, 320×568 and 568×320. Logs and screenshots go in `build/`.
- `package_builds.py` requires a clean checkout and verifies the commit and checksums against the records for both builds. It saves a manifest and packages the Web build without keys or signing logs. The browser check is tied to the SHA-256 of the current PCK. Run the checks and exports from the same commit before packaging.

The `Godot headless checks` CI workflow runs `check.sh`. It downloads the Godot binary and templates from the exact official release and verifies pinned SHA-512 checksums. PRs and main export both platforms using JDK 17 and the SDK Platform 36/build-tools 36.1.0 already installed on ubuntu-24.04. A missing tool stops the build. The job does not install the SDK or accept licenses. The prebuilt APK template requires neither NDK nor CMake.

CI creates a temporary test key for every run, so it needs no persistent secrets. The key and environment file stay on the temporary runner and are excluded from uploads. Installing an APK from a different run may require uninstalling the previous test. A manual workflow run produces an Actions archive with the APK, Web ZIP, exact source commit, SHA-256 checksums and public apksigner/aapt reports, retained for 14 days. PR checkouts use the PR head SHA rather than the temporary merge commit. To download, sign in to GitHub with read access. See [how to request a build](../README.md#download-builds). Chromium testing is local. A successful CI export still needs a separate runtime test in a browser or on an Android device.

## Test signing and phone checks

`create_debug_key.py` creates a dedicated technical test key outside the repository, with a private environment file and mode 0600. Running it again preserves existing files. Keep these files out of `build/`, Library, PRs and Git. This key is for technical tests only and is separate from other projects’ release keys and any future publication setup.

Godot reads `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `GODOT_ANDROID_KEYSTORE_DEBUG_USER` and `GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD`. Avoid `--verbose` and shell tracing during export because tools may print debug credentials. Reinstalling while retaining data requires the same key and package. Since the key lives outside Git, if the cloud snapshot is lost, restore the private signing files from a separate backup arranged by the owner, or uninstall the old test before installing with a new key.

The APK uses `org.ilyasyoy.stackattack.techtest`, versionCode 12, versionName 0.3.1-workshop-prototype, min API 24, target/compile API 36, arm64-v8a and `debuggable`. It currently includes only this ABI. The orientation sensor allows portrait and landscape, and system bars stay visible. To test on a phone, install the APK and go through menu → game → pause/loss → restart/menu. Check buttons, rotation, sound, vibration and saves. Increase versionCode for subsequent test versions.

## Verification results and limits

On November 14 the previous technical scene passed import, GDScript tests, headless startup, Web export and Playwright checks at six viewport sizes on macOS 27.0.1 / Apple M2 with Godot 4.7.2 and Chrome 157.0.8103.79. The Web build was also checked manually in Chrome and Safari, including keyboard input in Safari. The editor opened the scene and the native Apple M2 run printed `STACK_ATTACK_TECH_READY`. Re-exporting for Web took about 4 seconds. Local reports and screenshots are in the corresponding checkout’s ignored `build/` directory.

On the cloud machine with Godot 4.6.3, headless checks and both builds passed. The Web build runs GDScript and receives input in Chromium. The APK was checked for signature, structure, ABI and alignment. Ilya confirmed that the previous technical APK worked on a phone. **The new playable prototype still awaits a phone test.** The agent has no physical Android device. Mobile browsers, touch on hardware, phone-specific cutouts and system bars, audio/vibration and performance also need device checks. Emulated touch and SwiftShader do not cover them.

Native graphical Godot startup in a cloud shell without DISPLAY/Wayland has yet to be tested. The Web build uses Compatibility/WebGL 2, runs single-threaded and uses neither GDExtension nor a PWA/service worker. Serve index.html over HTTP/HTTPS. Opening it as a local file is unsupported. At this stage, no site or release had been published.

The first technical milestone passed its checks, including Ilya’s phone test. The first playable prototype is now ready for Ilya to assess its gameplay, balance and art. See the [prototype description](prototype.md).

## Official sources

- [Godot 4.7.2 binaries and templates](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)
- [Android configuration for this release](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/platform/android/java/app/config.gradle)
- [Signing variables for this release](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/platform/android/export/export_plugin.h)
- [Godot 4.7 command line](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- [Android export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html)
- [Web export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)
