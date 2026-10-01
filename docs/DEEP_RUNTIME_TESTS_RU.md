# Глубокие тесты на реальной CDDA

`.github/workflows/deep-runtime.yml` — тяжёлый compatibility/diagnostic слой.
Он не заменяет обычный CI и не должен запускаться на каждый commit без причины.

## 1. Official release binary

На Windows скачивается официальный release для точного target из
`catalog/targets`.

Проверяется:

- commit из `VERSION.txt`;
- vanilla baseline;
- каждый JSON component;
- profiles;
- combined stack;
- stdout/stderr/debug evidence и content hashes.

Для dependency `mod_interactions` используется capability probe точного игрового
binary. Если upstream `--check-mods` на этой версии сломан, defer применяется
только к затронутому dependency graph; остальные root-моды продолжают проходить
native validator.

## 2. Реальный installation/lifecycle matrix

Workflow собирает тот же installer, который получает пользователь, и проверяет
реальную файловую установку:

`clean -> install -> validate -> repeat -> update -> validate -> rollback`.

Проверяются также негативные сценарии: повреждённый ZIP, duplicate mod IDs,
незавершённая транзакция и другие contract failures.

Installer использует durable transaction/journal под
`<game>/_CDDA-Mods/transactions`, но transient extraction и validation выполняет
под коротким `%TEMP%\CDM-*`. Это необходимо для Windows PowerShell 5.1 и длинных
CatLauncher paths; глубокие деревья Secronom не должны упираться в legacy MAX_PATH.

## 3. Exact-source cata_test

Точный CDDA source commit checkout-ится отдельно. В него инжектируются только
repository-owned test probes, после чего один раз строится `tests/cata_test`.

Отдельные suites проверяют components, profiles и `combined-all-json`.
AXIOM имеет собственный lifecycle probe; content probes имеют отдельный tag
`[cdda_mods_content]`, исключённый из обычных component selectors.

## 4. Object-level content audit

Четыре shards выполняются независимо:

- **items** — создание/валидность repository-visible item types;
- **recipes** — consistency и создание реальных item-results/byproducts без
  ложных требований к practice/nested/blueprint recipes;
- **vehicles** — vehicle parts/base items и ненулевые vehicle prototypes;
  служебный vanilla prototype `none` исключён как sentinel;
- **overmap** — terrain/special IDs с исключением служебных null sentinels.

Это не просто загрузка JSON: probe проходит engine registries после полной
инициализации данных.

## Inherited upstream debt

Pinned известные upstream/interaction failures описаны отдельно и никогда не
превращаются в общий whitelist.

Для автоматической сертификации нового experimental допускается
`--portable-inherited-debt`: старая сигнатура принимается только при строгом
совпадении ожидаемых IDs/классов/счётчиков. Любое новое отклонение fatal.

## Актуальные контрольные точки

- baseline `0546`: normal exact-source suites и content audit подтверждены;
- `1040`: official release loader и exact `cata_test` build прошли; targeted
  Aftershock Prime Gryphon vehicle/parts runtime — GREEN;
- старый временный `1040` content-recheck был запущен до portable-debt режима,
  поэтому его формальные red items/overmap не являются текущим правилом verdict;
- `1124` candidate уже прошёл current generic harness:
  exact-source combined + items + recipes + vehicles + overmap — GREEN.

## Что не считать доказательством

- успешный JSON parse;
- обычный package CI без exact-game runtime;
- старый report после изменения payload;
- успех vanilla вместо успеха мода;
- совпадение только номера experimental без точного commit.
