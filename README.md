# Neversalimus CDDA Mods

Единый репозиторий восстановленных и поддерживаемых модов Cataclysm: Dark Days Ahead.
NCMM host/runtime и актуальные native-модули ведутся отдельно в
[Neversalimus/NCMM](https://github.com/Neversalimus/NCMM).

## Поддерживаемые цели

| CDDA | Commit | Состояние |
|---|---|---|
| experimental-2026-09-23-0546 | `e262adb299a7613b4aedc5f12c08fe0413c56a84` | поддерживается |
| experimental-2026-10-01-1040 | `3f7fb352bf492ba521bd9408a0c9f6ce239e8d83` | поддерживается |

Совместимость определяется не номером версии, а точным release tag + source commit.
Новые experimental автоматически обнаруживаются и проходят отдельную сертификацию
до добавления в `catalog/targets`.

На 1 октября 2026 кандидат `2026-10-01-1124`
(`cb7701daa21338fffbbeb4b8c03bd3e26b2a0cb5`) прошёл official release loader,
exact-source combined suite и все четыре content shards. Его первый promotion-run
не был применён, потому что `main` изменился во время длительной проверки; target
не считается опубликованным, пока повторная сертификация не завершит promotion.

## Компоненты

| Компонент | Версия в этом репозитории | Тип |
|---|---:|---|
| AXIOM-7 | 0.8.2.8-r2 | JSON |
| Blazemod Revival | 0.5.5-r9 | JSON |
| Secronom Revival | 1.5.1-r5 | JSON |
| Secronom+ Revival | 0.3.4-r5 | JSON |
| Aftershock Prime | 0.1.14a-r6 | JSON |
| Aftershock Prime / Mind Over Matter | 0.1.14a-r2 | JSON compat |
| Tankmod Revived | 2026.9.23.4-r7 | JSON |
| [Изнанка: Сшитый посёлок](mods/iznanka/README.md) | 0.2.0-r1 | JSON + собственные тайлы |
| UndeadPeople Hybrid v3 | 3.1.1-r5 | tileset |
| Advanced World Settings | 0.6.1-r3 | native source snapshot, installer-disabled |
| Survivor Progression | 0.9.15-r2 | native source snapshot, installer-disabled |

`profile:all-content` устанавливает AXIOM-7, Blazemod, Secronom+, Aftershock Prime,
Tankmod и UndeadPeople; зависимость Secronom добавляется автоматически.
MoM-compat включается отдельно только при использовании Mind Over Matter.
AWS/Survivor из этого репозитория не являются текущими runtime-модулями NCMM.

`profile:iznanka` устанавливает Изнанку и UndeadPeople Hybrid v3. Два маршрута
экспедиции рассчитаны только на `experimental-2026-10-06-1807` /
`074aa98bd5be3de4c35f154082db32a0e63bb0f1`. Включите мод при создании мира;
вход находится у редкого лесного разлома. [Проверки пакета](mods/iznanka/VALIDATION.md).

Модовые тайлсеты Blazemod, Secronom и Tankmod явно совместимы с внутренним ID
`UndeadPeople_0J_Hybrid_v3`; Secronom+ отдельного sprite sheet не имеет и использует
графику базового Secronom.

Сгенерированная графика прошла полный поячеечный аудит 9 октября: исправлены
178 спрайтов для 186 ID; привязки и геометрия тайлсета сохранены.
[Сравнения и полный отчёт](mods/undeadpeople/art-review/README.md).

## Установка

Скачать полный `CDDA-Mods-Installer.zip`, распаковать его целиком и запустить
`INSTALL.cmd`. Python, Git, Visual Studio и компиляция CDDA игроку не нужны.

Инсталлятор:

- находит CatLauncher/portable/обычные установки CDDA;
- определяет точный build по `VERSION.txt`;
- выбирает пакет только для совпадающего commit;
- проверяет SHA-256 архива и каждого payload-файла;
- распаковывает пакеты в короткий `%TEMP%\CDM-*`, чтобы не упираться в старый
  Win32 MAX_PATH под Windows PowerShell 5.1;
- проверяет JSON-моды через точный игровой validator на изолированной копии data;
- сохраняет backup/journal в `<game>/_CDDA-Mods/transactions`;
- при ошибке выполняет групповой rollback;
- не меняет saves и не включает моды в существующих мирах автоматически.

Пример:

```powershell
.\Install-Mods.ps1 -GameRoot 'C:\Games\CDDA' -Profile all-content
.\Install-Mods.ps1 -GameRoot 'C:\Games\CDDA' -Profile secronom
.\Install-Mods.ps1 -GameRoot 'C:\Games\CDDA' -Profile iznanka
.\Install-Mods.ps1 -GameRoot 'C:\Games\CDDA' -Update
.\Install-Mods.ps1 -GameRoot 'C:\Games\CDDA' -Rollback 'ИД_ТРАНЗАКЦИИ'
```

На `2026-10-01-1040` реальная установка `profile:all-content` через CatLauncher
успешно прошла isolated validator и завершилась `Exit code: 0`.
Для build-ов, где upstream `--check-mods` неправильно обрабатывает dependency
`mod_interactions`, installer автоматически определяет capability и откладывает
только опасный граф на exact-source `cata_test`; остальные проверки не пропускаются.

## Автосертификация новых experimental

`.github/workflows/experimental-watch.yml` раз в час ищет новые официальные
experimental releases. Незнакомый release отправляется в
`.github/workflows/experimental-certify.yml`.

Candidate не добавляется в поддерживаемые targets заранее. Сначала выполняются:

1. official Windows release loader;
2. exact source build `cata_test`;
3. full `combined-all-json`;
4. object-level `items`, `recipes`, `vehicles`, `overmap`;
5. строгая проверка известного inherited upstream debt.

Только полный GREEN разрешает promotion в `main`. Если `main` изменился во время
долгой проверки, актуальная версия workflow не должна публиковать устаревший
результат и ставит кандидата на повторную сертификацию.

Подробности: [docs/COMPATIBILITY_RU.md](docs/COMPATIBILITY_RU.md).

## Глубокая проверка

`.github/workflows/deep-runtime.yml` остаётся тяжёлым релизным/диагностическим
контуром, а не обязательным тестом каждого push. Он проверяет официальный бинарник,
реальный installation matrix, exact-source suites и object-level content audit.

Подробности: [docs/DEEP_RUNTIME_TESTS_RU.md](docs/DEEP_RUNTIME_TESTS_RU.md).

## Структура

- `mods/<id>/manifest.json` — версия, ревизия, зависимости и target mapping;
- `mods/<id>/content` — текущий JSON/tileset payload;
- `mods/<id>/native` — сохранённые native source snapshots;
- `catalog/targets` — поддерживаемые точные builds;
- `catalog/certifications` — provenance автоматически промоутированных targets;
- `installer` — Windows installer;
- `tools` — maintenance/runtime probes;
- `history` — исторические версии, не являющиеся текущим payload;
- `docs` — актуальная эксплуатационная документация.

Источником истины являются текущий `main`, manifests, target files и результаты
Actions. Старый ZIP или память чата не заменяют repository state.

Авторство и лицензии сторонних материалов сохраняются. См.
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
