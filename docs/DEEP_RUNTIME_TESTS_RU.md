# Глубокие тесты на реальной CDDA

Этот слой намеренно отделён от обычного CI. Он предназначен для редких,
дорогих проверок совместимости и релизных проходов, а не для каждого коммита.

## Что проверяется

Workflow `.github/workflows/deep-runtime.yml` работает в два слоя.

### 1. Official release binary

На Windows скачивается официальный release CDDA, соответствующий точному
`catalog/targets/<target>.json`.

Проверяется:

- SHA игры из `VERSION.txt` должен в точности совпасть с каталогом;
- сначала проходит чистая `dda`, чтобы ошибка самой базы не засчиталась как
  ошибка мода;
- каждый JSON-мод запускается отдельно через настоящий `--check-mods`;
- зависимости автоматически добавляются из manifest;
- проверяются repository profiles;
- проверяется общий стек всех JSON-модов;
- stdout/stderr/debug.log сохраняются как artifact;
- отчёт содержит SHA содержимого каждого tested payload.

То есть старый успешный отчёт не может автоматически сертифицировать изменённый
мод.

### 2. Installation / lifecycle matrix на настоящей игре

На той же официальной Windows-сборке строится реальный `dist` и запускается именно
тот `Install-Mods.ps1`, который получает пользователь. Это не mock файловой системы.

Для каждого JSON-мода выполняется последовательность:

`clean state -> install -> native --check-mods -> repeat install -> --check-mods -> update -> --check-mods -> rollback`

Отдельно выполняются общий JSON-стек и профиль `all-content`, включая установку и
rollback тайлсета. После установки проверяется уже **live `data/mods` игры**, а не
копия исходников из репозитория.

Негативная матрица дополнительно требует корректного отказа при:

- повреждённом ZIP пакета;
- двух живых копиях одного mod ID;
- незавершённой предыдущей транзакции.

Логи каждого шага и сводный `matrix-summary.json` сохраняются как artifact.

### 3. Exact source + cata_test

GitHub Actions отдельно делает checkout **точного commit CDDA**, указанного в
target, собирает родной `tests/cata_test`, копирует наши JSON-моды в
`data/mods` и запускает тесты CDDA с `--mods=...`.

Это важнее простого JSON parser gate: тестовый runtime CDDA загружает реальные
регистры игры, зависимости, mapgen, EOC, предметы, рецепты, транспорт и прочие
типы данных в тех же внутренних системах, которые использует сама игра.

Режимы:

- `load` — только `[force_load_game]` для каждого мода/профиля/общего стека;
- `full` — `force_load_game` + полный не-slow test pass для каждого набора;
- `exhaustive` — всё из `full`, а на общем стеке дополнительно slow и
  crafting_skill_gain группы.

`full` — нормальный глубокий режим. `exhaustive` оставлен для редких
релизных/аудитных проходов.

## Почему это не мешает разработке

Deep workflow **не имеет** триггеров `push` и `pull_request`.
Обычные ветки и PR продолжают выполнять только быстрый `ci.yml`.

Ручной запуск всегда доступен через Actions -> **Deep real-CDDA runtime**.

Плановый запуск раз в неделю включён по умолчанию. Это подходит текущему режиму,
где моды меняются редко и можно позволить длинную проверку. Для перехода в
интенсивную разработку достаточно создать repository variable:

`CDDA_DEEP_TESTS_ENABLED=false`

После этого schedule не запускает тяжёлые jobs. Ручной `workflow_dispatch`
остаётся доступен. Чтобы вернуть недельную проверку, удалить variable или поставить
любое значение, кроме `false`. Никакие workflow-файлы менять не нужно.

## Что сознательно не входит сюда

- `advanced_world_settings` и `survivor_progression` — native NCMM modules.
  Они не могут корректно загружаться ванильной CDDA без внешнего NCMM host.
  Их compile/runtime contract тестируется отдельно вместе с NCMM.
- tileset проходит структурную проверку в обычном CI; ванильный
  `--check-mods` не проверяет графический рендер tileset.
- успешный `--check-mods` или `cata_test` не заменяет ручной UX smoke-test
  миссий, диалогов и конкретных игровых сценариев. Но это уже гораздо глубже
  статической JSON-валидации и хорошо подходит для автоматического регрессионного
  барьера.

## Локальный запуск

Показать автоматически вычисленную матрицу:

```sh
python tools/deep_cdda_runtime.py plan --target experimental-2026-09-23-0546
```

Проверить уже скачанную точную CDDA:

```sh
python tools/deep_cdda_runtime.py run-release \
  --game-root C:/Games/CDDA \
  --target experimental-2026-09-23-0546 \
  --out build/deep-release
```

Если есть собранный exact-source `tests/cata_test`:

```sh
python tools/deep_cdda_runtime.py run-source \
  --cdda-root external/cdda \
  --target experimental-2026-09-23-0546 \
  --depth full \
  --out build/deep-source
```
