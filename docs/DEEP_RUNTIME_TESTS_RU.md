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
- скачанный GitHub Release asset проверяется по опубликованному SHA-256 digest;
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

### 2. Exact source + cata_test

GitHub Actions отдельно делает checkout **точного commit CDDA**, указанного в
target, сверяет фактический `git rev-parse HEAD`, один раз собирает родной
`tests/cata_test`, а затем раздаёт этот бинарник параллельной матрице. Каждый
JSON-мод, профиль и общий стек запускаются в отдельном чистом checkout CDDA с
`--mods=...`. Одновременно работают не более трёх тяжёлых runtime jobs, поэтому
длинный тест одного мода не блокирует все остальные и не съедает общий 6-часовой
лимит одного runner.

Это важнее простого JSON parser gate: тестовый runtime CDDA загружает реальные
регистры игры, зависимости, mapgen, EOC, предметы, рецепты, транспорт и прочие
типы данных в тех же внутренних системах, которые использует сама игра.

Режимы:

- `load` — только `[force_load_game]` для каждого мода/профиля/общего стека;
- `full` — `force_load_game` + основной upstream-проход
  `~[slow] ~[.],starting_items` для **каждого** набора. Это включает широкий
  engine regression surface и отдельно захватывает создание стартового персонажа;
- `exhaustive` — всё из `full` + complementary slow-проход
  `[slow] ~starting_items` для **каждого** набора, то есть практически весь
  non-hidden test surface CDDA с соответствующим модом загруженным.

`full` — нормальный глубокий режим. `exhaustive` оставлен для редких
релизных/аудитных проходов.

## Почему это не мешает разработке

Deep workflow **не имеет** триггеров `push` и `pull_request`.
Обычные ветки и PR продолжают выполнять только быстрый `ci.yml`.

Ручной запуск всегда доступен через Actions -> **Deep real-CDDA runtime**.

Плановый запуск раз в неделю существует, но по умолчанию фактически выключен.
Он выполняется только если repository variable:

`CDDA_DEEP_TESTS_ENABLED=true`

Чтобы перейти в интенсивный режим разработки, достаточно удалить эту variable
или поставить другое значение. Никакие workflow-файлы менять или комментировать
не нужно. Для плановых прогонов дополнительно можно задать
`CDDA_DEEP_TESTS_TARGET` и `CDDA_DEEP_TESTS_DEPTH`; без них используются
текущий закреплённый target и режим `full`.

## Что сознательно не входит сюда

- `advanced_world_settings` и `survivor_progression` — native NCMM modules.
  Они не могут корректно загружаться ванильной CDDA без внешнего NCMM host.
  Их compile/runtime contract тестируется отдельно вместе с NCMM.
- tileset проходит структурную проверку в обычном CI; ванильный
  `--check-mods` не проверяет графический рендер tileset.
- `cata_test` реально создаёт персонажей, карты/overmap/submap-состояния и
  прогоняет engine save/load-пути в тех тестах CDDA, которые входят в выбранный
  selector, но это всё ещё не то же самое, что интерактивно пройти UI создания
  мира и несколько игровых дней;
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
  --suite component-axiom_7 \
  --out build/deep-source
```
