# Stack Attack

Самостоятельная 2D-аркада на **Godot 4.7.2 + GDScript** для Android и Web. Два щипца на рельсах привозят ящики. Игрок прыгает, толкает деревянные ящики и заполняет нижний ряд. В игре есть локальная статистика, история матчей, настройки, авторские спрайты и звуки.

Стрелки влево и вправо двигают героя, пробел и стрелка вверх — прыжок. Нажмите E или кнопку с круговыми стрелками, чтобы подобрать или обменять вещь. F включает действие слота головы, G — слота рук. Клавиатура и экранные кнопки позволяют одновременно двигаться, удерживать колпак часовщика и стрелять из рогатки.

Каждый уничтоженный деревянный ящик с вероятностью 10% оставляет одну из 12 равновероятных вещей, с вероятностью 3% — капкан. В остальных случаях ящик пуст. Железные ящики составляют 10% новых грузов, двигаются с сильными руками и уходят в приёмник вместе с полным нижним рядом. Правила снаряжения и столкновений собраны в [описании игры](docs/prototype.md).

## Запуск Web из исходников

Команды выполняются из корня репозитория. Для Linux и macOS нужны обычная сборка Godot 4.7.2 (GDScript), Bash, Git, Make, GNU `timeout`, `curl`, `unzip`, `shasum`, Python 3.13 и `uv`. Сверьте вывод `godot --version` с [.godot-version](.godot-version). Если пакетный менеджер предлагает другую версию, возьмите редактор из [архива Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/).

На macOS инструменты командной строки можно установить через Homebrew:

```bash
brew install coreutils python@3.13 uv
export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
```

Подготовьте окружение Python и шаблоны Web, затем запустите игру:

```bash
uv sync --locked --group web --python 3.13
bash scripts/install_web_templates.sh
make web
```

Скрипт сверяет SHA-512 официального архива шаблонов. `make web` собирает игру и открывает `http://127.0.0.1:8765/`. Нужен браузер с WebGL 2. Чтобы выбрать другой порт, выполните `make web PORT=8766`. Чтобы остановить сервер, нажмите Ctrl+C. Статистика и сохранения привязаны к адресу и порту.

Для работы в редакторе выполните `godot --editor --path .`. Для проверки импорта, игровых правил и запуска сцены используйте `bash scripts/check.sh`. Браузерный тест запускается отдельно:

```bash
bash scripts/export.sh web
uv run --locked --group web python scripts/check_web.py
```

На Linux тест ищет Chromium в `/usr/bin/chromium`, на macOS — Google Chrome. Другой установленный браузер можно указать через `CHROMIUM_BIN`.

## Сборка тестового APK на Linux

Установите JDK 17 с `keytool`, Android SDK Command-line Tools, Platform Tools, SDK Platform 36 и Build Tools 36.1.0. Установите полные **export templates 4.7.2.stable** через менеджер шаблонов Godot. Скрипт из раздела Web извлекает только Web-шаблоны. В этом проекте APK собирается из готового шаблона без Gradle.

Укажите `JAVA_HOME` и `ANDROID_HOME`, добавьте `$JAVA_HOME/bin` в `PATH`. В Godot откройте **Editor Settings → Export → Android**, укажите Java SDK Path и Android SDK Path. Подготовьте ключ для тестовых сборок в каталоге вне репозитория:

```bash
python3 scripts/create_debug_key.py "$HOME/.local/share/stack-attack/debug-signing"
source "$HOME/.local/share/stack-attack/debug-signing/debug-signing.env"
bash scripts/export.sh android
```

При необходимости укажите созданный файл keystore в поле **Debug Keystore** редактора. Команда проверяет подпись и выравнивание APK. Результат — `build/android/stack-attack-prototype-debug.apk`, ARM64, Android API 24+. Для обновления тестовой установки нужен тот же ключ. Удаление старой установки с другой подписью удалит и её локальные данные.

## Работа в Cockpit

В подготовленном окружении Cockpit команда `source /workspace/setup-stack/env.sh` в новом shell выбирает Godot, JDK, Android SDK и Chromium. Эти инструменты и существующий каталог debug-подписи находятся за пределами checkout. После активации перейдите в свой checkout и используйте те же команды проверки и экспорта. Вне Cockpit настройте инструменты по разделам выше.

## Готовые сборки

На каждом PR и при push в `main` задание `headless` проверяет игру и экспортирует Android и Web. Эти проверки завершаются ошибкой при сбое тестов или экспорта.

Для получения архива нужен ручной запуск с правом записи: **Actions → Godot headless checks → Run workflow**. Выберите `main` или нужную ветку этого репозитория с данным workflow. Эквивалент в CLI — `gh workflow run check.yml --ref main`. Ручной запуск повторяет проверки и экспорт для выбранной ревизии, упаковывает файлы и загружает их. После успешной загрузки в разделе **Artifacts** доступен архив на 14 дней. Если исчерпана квота хранения, ручной запуск покажет ошибку на шаге загрузки. Для скачивания нужен вход в GitHub и доступ на чтение репозитория. Архив содержит тестовый APK, Web ZIP, идентификатор коммита, SHA-256 и отчёты Android. CI создаёт временный ключ на каждый запуск.

Распакуйте Web ZIP, запустите сервер из каталога с папкой `web/` и откройте адрес в браузере:

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory web
```

Адрес игры — `http://127.0.0.1:8765/`. Рядом с `index.html` лежат `GODOT_LICENSE.txt` и `GODOT_COPYRIGHT.txt`. Их можно открыть через тот же HTTP-сервер. Для локальной упаковки чистого коммита после `bash scripts/export.sh all` и полной браузерной проверки используйте `python3 scripts/package_builds.py`.

## Материалы и лицензии

- [Правила игры и управление](docs/prototype.md)
- [Происхождение спрайтов, шрифта и звука](docs/assets.md)
- [Лицензия Godot](notices/GODOT_LICENSE.txt) и [уведомления о компонентах](notices/GODOT_COPYRIGHT.txt). В APK их можно прочитать, открыв его как ZIP и перейдя в `assets/notices/`.
- Отдельная лицензия для кода и игровых материалов проекта пока не выбрана.
