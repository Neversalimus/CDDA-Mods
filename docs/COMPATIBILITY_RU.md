# Новая experimental или stable

1. Выбрать точный release tag CDDA. `prepare-target` получает настоящий commit
   тега через GitHub API. `target_commitish: master` не является фиксацией версии.
2. Назвать моды: один, несколько или `all`. Команда копирует только выбранные
   варианты в `mods/<id>/variants/<target>/`, оставляя старый вариант на месте.
   Новая цель начинает со статуса pending. Для зависимости тоже подготовить вариант.
3. Сопоставить схемы JSON/удалённые IDs, зависимости, EOC, рецепты, mapgen и
   взаимодействия с изменениями CDDA. Внести минимальные патчи нужного варианта.
4. Запустить `validate` и `build`. Это синтаксис/структура, а не игровая проверка.
5. Скачать точную сборку CDDA и проверить её VERSION.txt. Запустить:

```sh
python tools/verify_game.py --game-root C:/Games/CDDA --target experimental-2026-09-23-0546 --mods axiom_7,blazemod --out build/check --timeout 240
python tools/modsuite.py record-validation --report build/check/report.json
```

Проверяются ваниль, каждый мод и общий набор через временный dependency-only мод.
Исходники проверяются по хешу: старый отчёт не сертифицирует новые файлы.
Ошибка ванили не считается успехом мода. Валидация работает в копии данных, с
отдельным userdir. Тайлсет/портреты копируются в datadir/gfx: в этой сборке движок
меняет путь к gfx при использовании --datadir.
6. Отдельно выполнить игровой smoke-test: загрузка копии существующего сохранения,
   создание мира, основные системы мода. Для AXIOM — миссии/KX; для Secronom —
   монстры/emit_fields; для Prime — hacking; для Blazemod — blobs и транспорт.
7. Поднять только версии/ревизии изменённых модов. Обновить changelog и каталог.
   Для общего релиза поднять suite_version. Tag должен быть `v<suite_version>`.
8. Проверить CI, затем создать tag. Release workflow публикует независимые ZIP,
   каталог, checksums и общий архив. В одном релизе могут быть варианты нескольких
   версий игры. Пользователь обновляет только нужные IDs.

Статусы: pending → static → load-tested → runtime-tested; blocked запрещает
установку. Инсталлер не выбирает случайный вариант, если новая игра неизвестна
или есть несколько кандидатов. `-AllowUntested` разрешает попытку локальной
валидации, не объявляет совместимость и не пропускает проверку JSON-модов.

Native: новая версия игры требует подходящего внешнего NCMM host. Здесь меняются
только модули. CI собирает DLL с exact SDK, но не компилирует CDDA на ПК игрока.
Survivor 0.9.15 требует API 1.8 и host с механиками cumulative v8.7.3; пока его контракт и DLL не
подтверждены вместе, пакет остаётся source-only. Не заменять его 0.9.0.

Native refresh: AWS 0.6.1 and Survivor 0.9.15 revision 1 from v8.7.3 are source-only. Old AWS 0.5.0 DLL is history-only; both current native installs are blocked pending compatible external API 1.8 host. Module source audits and g++ checks passed. No host/game installer ran.
