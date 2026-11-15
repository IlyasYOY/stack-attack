# Облачное окружение и сборки прототипа

Последняя подтверждённая версия опубликованного окружения проверена 11 ноября 2026 на Linux Debian 13.6 x86_64 с Godot 4.6.3. Текущий checkout переведён на **4.7.2** для установки редактора через Homebrew и локальной проверки Web. Обновление опубликованного cloud snapshot ещё не подтверждено: его выполняет отдельный агент по [промпту настройки](cloud-setup-prompt.md).

Скрипты установки облачного окружения находятся вне checkout в `/workspace/setup-stack`. Активация `/workspace/setup-stack/env.sh` после обновления должна выбирать точную сборку из `.godot-version`. Локальные инструкции macOS — в README. Команды проверки и экспорта проекта ничего не устанавливают и не принимают лицензии; отдельный `install_web_templates.sh` устанавливает Web-шаблоны.

## Закреплённый инструментарий

| Компонент | Требуемая версия |
| --- | --- |
| Godot, обычная сборка без .NET | 4.7.2.stable.official.ed1daf0bf |
| Export templates | 4.7.2.stable |
| JDK / javac | Temurin 17.0.21+9 / 17.0.21 |
| Android command-line tools | 19.0 |
| Android platform-tools | 37.0.1, build 15733141 |
| Android SDK Platform | API 36, revision 2 |
| Android build-tools | 36.1.0 |
| NDK | r29 / 29.0.14206865 |
| CMake | пакет 3.10.2.4988404, executable 3.10.2 |
| Chromium / Python Playwright | 156.0.8078.79 / 1.62.0 |
| Pillow | 13.0.0 (ассеты и анализ скриншотов) |

Godot и Web-шаблоны новой версии установлены локально на macOS 14 ноября 2026. Версии остальных облачных инструментов в таблице взяты из проверки 11 ноября и требуют повторной проверки агентом настройки. Playwright и Pillow закреплены в группе `web` и `uv.lock`. Использовать Python 3.13 в проектной `.venv`. На macOS тест выбирает установленный Chrome, в cloud — `/usr/bin/chromium` либо `CHROMIUM_BIN`.

В каждом новом shell выполнять `source /workspace/setup-stack/env.sh`. Без активации `java` выбирает системную Java 21, а `javac`, `adb` и `sdkmanager` не доступны в PATH. Значения JAVA_HOME/ANDROID_HOME сами по себе не заменяют активацию PATH.

Godot и шаблоны должны совпадать. `.godot-version` и `scripts/common.sh` проверяют точную сборку движка; в Linux шаблоны находятся в `${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable`. Настройки Android нужно перенести в `editor_settings-4.7.tres`: Java SDK Path и Android SDK Path должны указывать на существующие JDK/SDK. Настройки 4.6 сами по себе не подтверждают готовность 4.7.

Точная конфигурация Android релиза 4.7.2 по-прежнему использует Java 17, SDK 36, build-tools 36.1.0 и NDK 29. Для воспроизведения закреплены параметры точного релиза, а не `latest`. Штатный APK использует готовый шаблон без Gradle; NDK/CMake в этой сборке не компилируют код.

## Повторение проверок

Из checkout после активации:

```bash
bash scripts/check.sh
python3 scripts/create_debug_key.py /workspace/stack-attack-local/debug-signing
source /workspace/stack-attack-local/debug-signing/debug-signing.env
bash scripts/export.sh all
uv sync --locked --group web --python python3.13
uv run --locked --group web python scripts/check_web.py
uv run --locked --group web python scripts/package_showcase.py
```

- `check.sh`: импорт, GDScript-проверки правил игры, экранов, управления, локального сохранения и смены ориентации; отдельный headless-запуск. Геометрия цельных меню проверяется также на Fold-размерах и с Android-строкой вибрации; все элементы должны оставаться в кадре без ScrollContainer. Таймаут и проверка ERROR в логах не позволяют принять зависание или ошибку импорта за успех.
- `export.sh`: debug Web и подписанный debug APK. Android-проверки: apksigner, aapt и zipalign с 16 KiB page alignment. Пароли передаются официальными переменными Godot, не записываются в export preset.
- `check_web.py`: временный localhost HTTP-сервер и Chromium с программным SwiftShader; мышь, клавиатура, одновременный multitouch на canvas, изменение размеров, полный цикл партии, пауза и оба перезапуска, оба поражения, цепочка, сохранение после reload и проверка реального аудиосигнала. Размеры: 1280×720, 720×1280, 390×844, 844×390, 320×568, 568×320. Логи и скриншоты — `build/`.
- `package_builds.py`: требует чистый checkout и совпадение commit/контрольных сумм с записями обеих сборок; сохраняет манифест, упаковывает Web без ключей и логов подписи. Проверка браузера привязана к SHA-256 текущего PCK. Команды проверки и экспорта нужно выполнить с того же commit перед упаковкой.

В CI `Godot headless checks` выполняется `check.sh`. Бинарный Godot и шаблоны скачиваются из точного официального релиза с закреплённой SHA-512. На PR и main выполняется экспорт обеих платформ: используются JDK 17 и уже установленные SDK Platform 36/build-tools 36.1.0 образа ubuntu-24.04. При их отсутствии сборка останавливается; SDK не устанавливается и лицензии не принимаются. NDK/CMake для готового APK-шаблона не нужны.

CI создаёт новый временный тестовый ключ на каждый run; постоянные secrets не требуются. Ключ и env-файл остаются на временном runner и не загружаются. Для установки APK из другого run может понадобиться удалить прежний тест. Приватный Actions artifact содержит APK, Web ZIP, точный исходный commit, SHA-256 и публичные отчёты apksigner/aapt; срок хранения — 14 дней. Checkout для PR закреплён на его head SHA, а не на временном merge commit. Для скачивания требуется вход в GitHub с доступом к приватному репозиторию. Проверка Chromium остаётся локальной; CI-экспорт сам по себе не подтверждает выполнение Web или APK на устройстве.

## Тестовая подпись и телефон

`create_debug_key.py` создаёт отдельный ключ только для технического теста, с приватным env-файлом и правами 0600, вне репозитория. Повторный запуск сохраняет имеющиеся файлы. Не переносить их в `build/`, Library, PR или Git. Это не release-ключ другого проекта и не настройка будущей публикации игры.

Godot читает `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `GODOT_ANDROID_KEYSTORE_DEBUG_USER` и `GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD`. Не запускать экспорт с `--verbose` или shell tracing: инструменты могут показать debug credentials. Для повторной установки с сохранением данных нужен тот же ключ и package. Хранение ключа вне Git означает, что после потери облачного snapshot нужно восстановить приватные signing-файлы из отдельно организованной владельцем копии либо удалить прежний тест перед установкой с новым ключом.

APK: `org.ilyasyoy.stackattack.techtest`, versionCode 12, versionName 0.3.1-workshop-prototype, min API 24, target/compile API 36, arm64-v8a, `debuggable`. Другие ABI пока не включены. Датчик разрешает портретную и альбомную ориентации; системные панели оставлены видимыми. Для проверки на телефоне: установить APK, пройти меню → партия → пауза/проигрыш → повтор/меню, проверить кнопки и поворот, звук, вибрацию и сохранение. При последующих тестовых версиях versionCode нужно увеличивать.

## Подтверждения и границы

Для предыдущей технической сцены 14 ноября на macOS 27.0.1 / Apple M2 с Godot 4.7.2 прошли импорт, GDScript-тест, headless-запуск, Web-экспорт и Playwright-проверка в Chrome 157.0.8103.79 на шести размерах окна. Web просмотрен вручную в Chrome и Safari. В Safari подтверждён клавиатурный ввод. Редактор открыл сцену, нативный запуск на Apple M2 выдал `STACK_ATTACK_TECH_READY`. Повторный экспорт Web занял около 4 секунд. Локальные отчёты и скриншоты находятся в игнорируемом `build/` соответствующего checkout.

На облачной машине с Godot 4.6.3 подтверждены headless-проверки и обе сборки; Web исполняет GDScript и получает ввод в Chromium. Сам APK проверен по подписи, структуре, ABI и alignment. Илья подтвердил успешную работу предыдущего технического APK на телефоне. **Новый игровой прототип на телефоне ещё не проверен**: реального Android-устройства у агента нет. Отдельно остаются mobile browser, touch на устройстве, вырезы/системные панели конкретных телефонов, audio/vibration и производительность. Эмуляция touch и SwiftShader их не заменяют.

Нативный графический запуск Godot в cloud shell без DISPLAY/Wayland не проверен. Web использует Compatibility/WebGL 2, single-threaded, без GDExtension и PWA/service worker. Требуется HTTP/HTTPS; открытие index.html как локального файла не поддерживается. Сайт и релизы не публиковались.

Первая техническая часть проверена, включая телефонную проверку Ильи. Теперь подготовлен первый играбельный прототип; его приёмка, баланс и художественная подача ещё ждут оценки Ильи. Подробнее — [описание прототипа](prototype.md).

## Официальные источники

- [Godot 4.7.2 binaries и templates](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)
- [Конфигурация Android точного релиза](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/platform/android/java/app/config.gradle)
- [Переменные подписи точного релиза](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/platform/android/export/export_plugin.h)
- [Командная строка Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- [Android export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html)
- [Web export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)
