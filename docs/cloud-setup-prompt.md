# Обновить cloud-окружение Stack Attack до Godot 4.7.2

Настрой существующее переиспользуемое cloud-окружение проекта `IlyasYOY/stack-attack` для Android и Web и проверь текущий играбельный прототип. Работа выполняется на cloud-машине.

## Целевая версия и исходное состояние

- Godot: обычная сборка без .NET, точный вывод `godot --version` — `4.7.2.stable.official.ed1daf0bf`.
- Export templates: `4.7.2.stable`, включая Android debug/release, Web single-threaded debug/release и необходимые данные движка.
- Рендерер Compatibility, Web без threads, GDExtension и PWA.
- Последний подтверждённый опубликованный snapshot: Debian 13.6 x86_64 с Godot 4.6.3. Репозиторий обычно находится в `/workspace/stack-attack`, setup — в `/workspace/setup-stack`, активация — `/workspace/setup-stack/env.sh`. Сначала проверь фактические пути и состояние выбранной машины.
- Для настройки используй основную ветку `main` репозитория `IlyasYOY/stack-attack` с обновлением проекта и CI до 4.7.2. Перед проектными проверками получи актуальную ревизию и проверь `.godot-version`.

Локальный редактор установлен через Homebrew; Web проверяется на Mac. Cloud нужен в том числе для Android-сборок. Обе платформы сохраняются.

## 1. Проверить среду и доступную ревизию

Прочитай `AGENTS.md`, `README.md`, `docs/plan.md` и `docs/cloud-environment.md` в доступном checkout. Проверь статус окружения и Git, сохрани существующие изменения. Используй доступный workflow настройки cloud, а не только одноразовую установку в терминале.

Сверь `.godot-version` с целевой полной строкой выше. Если обновлённая ревизия ещё не доступна, подготовь инструменты 4.7.2 вне checkout и проверь их версии. Проектные тесты отметь как ожидающие переноса обновлённой ревизии. Не меняй старый pin и не обходи строгую проверку версии ради зелёного результата. Для полной проверки потребуется checkout уже обновлённого проекта.

## 2. Обновить сохраняемый инструментарий

Сначала сохрани предыдущие setup/env-файлы и проверь расположение существующего debug-ключа. Сохрани его, alias, пароль и приватный env-файл без вывода значений в чат и логи. Ключ остаётся вне checkout; его замена ломает установку APK поверх прежней версии.

Для Linux x86_64 используй официальные артефакты релиза `4.7.2-stable`:

- `https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
- SHA-512: `9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65`
- `https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz`
- SHA-512: `ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079`

Официальный альтернативный адрес шаблонов: `https://downloads.godotengine.org/?version=4.7.2&flavor=stable&slug=export_templates.tpz`. Проверка полного SHA-512 обязательна независимо от зеркала. Для другой архитектуры выбери соответствующий официальный бинарник и проверь его по `SHA512-SUMS.txt` этого же релиза.

Обнови сохраняемые setup-скрипты и `/workspace/setup-stack/env.sh`, чтобы новый shell выбирал целевой Godot через PATH или `GODOT_BIN`. Шаблоны в Linux должны оказаться в `${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable`. Установи `android_debug.apk`, `android_release.apk`, `web_nothreads_debug.zip`, `web_nothreads_release.zip`, `icudt_godot.dat`, `version.txt`.

Сохрани существующие JDK/Android SDK, если они соответствуют требованиям точного релиза:

- Java/JDK 17;
- Android SDK Platform 36;
- build-tools 36.1.0;
- NDK 29.0.14206865; для готового APK без Gradle NDK и CMake не компилируют код.

Проверь требования по `https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/platform/android/java/app/config.gradle`. В `editor_settings-4.7.tres` настрой реальные пути Java SDK, Android SDK и существующего debug-keystore. Сохрани `export/android/shutdown_adb_on_exit = false`. Активация должна согласованно задавать PATH, JAVA_HOME и ANDROID_HOME.

Проверь `timeout`, `uv`, Python 3.13 и Chromium. Playwright и Pillow устанавливай в проектную `.venv` по `uv.lock`, группа `web`. `CHROMIUM_BIN` задай для фактического пути браузера, если он отличается от `/usr/bin/chromium` в Linux.

## 3. Проверить обновлённый checkout

В новом shell из нужной ревизии:

```bash
source /workspace/setup-stack/env.sh
cd /workspace/stack-attack
godot --version
uv sync --locked --group web --python python3.13
bash scripts/check.sh
bash scripts/export.sh web
uv run --locked --group web python scripts/check_web.py
```

Проверь PASS и отчёт `build/web-check.json`. Полный браузерный тест проверяет меню и спрайты, клавиатуру, мышь и multitouch, поворот, паузу, перезапуск, оба поражения, цепочку, сохранение после reload и фактический звуковой сигнал. Проверь созданные скриншоты и отсутствие ошибок страницы и сетевых запросов. Отчёт должен соответствовать текущему PCK.

Затем активируй существующий приватный signing env и выполни:

```bash
bash scripts/export.sh android
```

Если отдельного ключа ещё нет, создай его штатным `scripts/create_debug_key.py` в каталоге вне checkout, затем активируй созданный приватный env. Существующие ключи сохраняй. Не используй shell tracing или verbose-вывод signing-команд.

Проверь `apksigner`, `aapt`, ABI arm64-v8a, package `org.ilyasyoy.stackattack.techtest` и 16 KiB zip alignment. Проверка APK по структуре и подписи не означает запуск на телефоне. Упаковку `package_builds.py` выполняй только при выполнении его требований к чистому commit; коммиты ради упаковки не создавай.

## 4. Сохранить и проверить переиспользуемость

Сохрани setup-конфигурацию и подготовленное окружение доступным в setup-чате способом. Если для Publish требуется действие владельца, сообщи точное действие. После публикации отдельно проверь новый экземпляр, запущенный из опубликованной версии: активацию, точную версию Godot, наличие шаблонов и повторение проверок. Если новый экземпляр недоступен, явно оставь эту проверку невыполненной.

В финальном отчёте укажи: ID/ревизию окружения при наличии, ревизию checkout, фактические версии и пути инструментов, выполненные проверки и оставшиеся ограничения. Отдельно обозначь состояние текущей машины, опубликованного snapshot и нового экземпляра. Публикация сайта, GitHub Release, изменение игровых правил, коммиты, merge и push в это поручение не входят.

---

Posted by GPT-6 using Codex
