# Облачное окружение и сборки прототипа

Опубликованное окружение восстановлено и проверено в новой задаче 11 ноября 2026 на Linux Debian 13.6 x86_64. Работа на компьютере Ильи не выполнялась. Скрипты установки окружения находятся вне checkout в `/workspace/setup-stack`; команды проекта ничего не устанавливают и не принимают лицензии.

## Закреплённый инструментарий

| Компонент | Проверенная версия |
| --- | --- |
| Godot, обычная сборка без .NET | 4.6.3.stable.official.7d41c59c4 |
| Export templates | 4.6.3.stable |
| JDK / javac | Temurin 17.0.21+9 / 17.0.21 |
| Android command-line tools | 19.0 |
| Android platform-tools | 37.0.1, build 15733141 |
| Android SDK Platform | API 36, revision 2 |
| Android build-tools | 36.1.0 |
| NDK | r29 / 29.0.14206865 |
| CMake | пакет 3.10.2.4988404, executable 3.10.2 |
| Chromium / Python Playwright | 156.0.8078.79 / 1.62.0 |
| Pillow | 13.0.0 (ассеты и анализ скриншотов) |

В каждом новом shell выполнять `source /workspace/setup-stack/env.sh`. Без активации `java` выбирает системную Java 21, а `javac`, `adb` и `sdkmanager` не доступны в PATH. Значения JAVA_HOME/ANDROID_HOME сами по себе не заменяют активацию PATH.

Godot и шаблоны должны совпадать. `.godot-version` и `scripts/common.sh` проверяют точную сборку движка; шаблоны находятся в `$XDG_DATA_HOME/godot/export_templates/4.6.3.stable`. Java SDK Path и Android SDK Path уже заданы в EditorSettings опубликованного окружения. В другом Linux-окружении эти пути нужно настроить на существующие JDK/SDK, а движок и шаблоны установить по указанным ниже официальным источникам.

Точная конфигурация Android релиза 4.6.3 использует SDK 36, build-tools 36.1.0 и NDK 29; документация общей ветки 4.6 ещё перечисляет SDK 35/NDK 28b. Для воспроизведения закреплены параметры точного релиза, а не `latest`. Штатный APK использует готовый шаблон без Gradle; NDK/CMake в этой сборке не компилируют код.

## Повторение проверок

Из checkout после активации:

```bash
bash scripts/check.sh
python3 scripts/create_debug_key.py /workspace/stack-attack-local/debug-signing
source /workspace/stack-attack-local/debug-signing/debug-signing.env
bash scripts/export.sh all
python3 scripts/check_web.py
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

APK: `org.ilyasyoy.stackattack.techtest`, versionCode 9, versionName 0.2.7-prototype, min API 24, target/compile API 36, arm64-v8a, `debuggable`. Другие ABI пока не включены. Датчик разрешает портретную и альбомную ориентации; системные панели оставлены видимыми. Для проверки на телефоне: установить APK, пройти меню → партия → пауза/проигрыш → повтор/меню, проверить кнопки и поворот, звук, вибрацию и сохранение. При последующих тестовых версиях versionCode нужно увеличивать.

## Подтверждения и границы

На облачной машине подтверждены headless-проверки и обе сборки; Web исполняет GDScript и получает ввод в Chromium. Сам APK проверен по подписи, структуре, ABI и alignment. Илья подтвердил успешную работу предыдущего технического APK на телефоне. **Новый игровой прототип на телефоне ещё не проверен**: реального Android-устройства у агента нет. Отдельно остаются mobile browser, touch на устройстве, вырезы/системные панели конкретных телефонов, audio/vibration и производительность. Эмуляция touch и SwiftShader их не заменяют.

Нативный графический запуск Godot в shell без DISPLAY/Wayland не проверен. Web использует Compatibility/WebGL 2, single-threaded, без GDExtension и PWA/service worker. Требуется HTTP/HTTPS; открытие index.html как локального файла не поддерживается. Сайт и релизы не публиковались.

Первая техническая часть проверена, включая телефонную проверку Ильи. Теперь подготовлен первый играбельный прототип; его приёмка, баланс и художественная подача ещё ждут оценки Ильи. Подробнее — [описание прототипа](prototype.md).

## Официальные источники

- [Godot 4.6.3 binaries и templates](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable)
- [Конфигурация Android точного релиза](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/platform/android/java/app/config.gradle)
- [Переменные подписи точного релиза](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/platform/android/export/export_plugin.h)
- [Командная строка Godot 4.6](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html)
- [Android export](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html)
- [Web export](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html)
