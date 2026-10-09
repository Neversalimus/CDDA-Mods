# Совместимость с новой CDDA

Графическая ревизия UndeadPeople 3.1.1-r5 от 2026-10-09 сохраняет все tile ID,
индексы, размеры листов и текущие target mappings. Аудит PNG и установочного ZIP
не добавляет новых заявлений об игровой совместимости; см.
[отчёт](../mods/undeadpeople/art-review/README.md).

Совместимость определяется точным release tag и source commit, а не только номером
experimental.

## Автоматический путь для experimental

Workflow `.github/workflows/experimental-watch.yml` запускается ежечасно и
обнаруживает новые официальные `cdda-experimental-*` releases.

Новый release отправляется в `.github/workflows/experimental-certify.yml`.
Candidate target создаётся только в рабочем checkout CI и не считается
поддерживаемым заранее.

Сертификация включает:

1. проверку static repository/package gate;
2. загрузку точного официального Windows release;
3. прогон vanilla/каждого JSON component/profile/combined stack через release loader;
4. checkout точного CDDA source commit;
5. сборку `tests/cata_test` с repository-owned probes;
6. full exact-source `combined-all-json`;
7. object-level shards:
   - `items`;
   - `recipes`;
   - `vehicles`;
   - `overmap`.

Известный inherited upstream debt допускается на новом candidate только через
`--portable-inherited-debt` и только при строгом совпадении сохранённой сигнатуры.
Новая ошибка, новый ID или другой класс сбоя остаются fatal.

После полного GREEN promotion job:

- повторно проверяет, что tested repository SHA не устарел;
- материализует target/manifests;
- пишет certification provenance;
- коммитит поддержку в `main`;
- запускает обычный Verify.

Актуальная workflow-логика не должна публиковать stale результат: если `main`
изменился во время проверки, candidate требуется проверить снова на свежем `main`.

## Поддерживаемые targets на 2026-10-01

- `experimental-2026-09-23-0546` /
  `e262adb299a7613b4aedc5f12c08fe0413c56a84`;
- `experimental-2026-10-01-1040` /
  `3f7fb352bf492ba521bd9408a0c9f6ce239e8d83`.

Candidate `2026-10-01-1124` / `cb7701da...` уже прошёл release loader,
exact-source combined и все четыре content shards, но первый promotion-run был
отклонён как stale после изменения `main`. Пока target не появился в
`catalog/targets`, он не считается опубликованной поддержкой.

## Ручной путь

Для stable, локальной отладки или намеренно выбранного target:

```sh
python tools/modsuite.py prepare-target --tag cdda-experimental-YYYY-MM-DD-HHMM --mods MOD_ID
python tools/modsuite.py validate
python tools/modsuite.py build
```

`prepare-target` разрешает настоящий tag commit через GitHub API и не использует
движущийся `target_commitish: master` как источник истины.

Старые variants/targets не должны молча заменяться новыми.

## Статусы manifest

`pending`, `static`, `load-tested`, `runtime-tested`, `blocked` — это
метаданные конкретного variant. Deep/candidate CI не должен задним числом менять
их без отдельного promotion/record-validation шага.

Поэтому runtime evidence в Actions и поле `validation` в старом manifest могут
временно различаться. При принятии релиза документация обязана явно указать такое
расхождение, а не выдавать `pending` за отсутствие всех runtime-тестов.

## Native

AWS/Survivor snapshots в этом репозитории installer-disabled. Совместимость
актуального NCMM host и текущих native-модулей проверяется в
`Neversalimus/NCMM`. Этот репозиторий не должен копировать туда host/runtime.
