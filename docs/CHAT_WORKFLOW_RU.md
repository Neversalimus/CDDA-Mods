# Работа в нескольких чатах

Источником истины служит текущий `main` репозитория, manifests, target/certification
files и GitHub Actions. Память чата и старые архивы — только вспомогательный контекст.

## Старт работы

В новом чате достаточно зафиксировать:

- репозиторий: `Neversalimus/CDDA-Mods`;
- нужный мод/инфраструктуру;
- точный CDDA target, если задача связана с совместимостью;
- запрет на изменения NCMM, если задача только про этот репозиторий.

Перед правкой нужно прочитать `AGENTS.md`, `README.md`, `docs/STATUS.md` и
manifest выбранного компонента, затем проверить remote HEAD и Actions.

## Параллельная работа

Если несколько чатов одновременно меняют код, предпочтительны отдельные
branches/worktrees. Общие конфликтные точки:

- `catalog/*`;
- `installer/*`;
- `.github/workflows/*`;
- один и тот же mod payload/manifest;
- глобальные docs.

Не делать force push и не перезаписывать чужой незаконченный diff.

## Новые experimental

Обычную новую experimental не нужно вручную объявлять совместимой.
`CDDA Experimental Watch` обнаруживает официальный release и запускает
`CDDA Experimental Compatibility`.

До полного GREEN candidate существует только внутри CI checkout. Promotion в
`catalog/targets` происходит после official loader + exact source + combined +
items/recipes/vehicles/overmap. Если `main` изменился, результат считается stale
и не должен публиковаться.

Для stable, нестандартного target или ручной отладки используется
`tools/modsuite.py prepare-target` с последующей exact-game проверкой.

## Перед завершением задачи

Проверить:

- обычный Verify and package;
- релевантные targeted/runtime tests;
- что docs не описывают старую версию как текущую;
- changelog изменённого мода;
- `docs/STATUS.md` и `docs/HANDOFF.md`.

Исторические документы в `history/*` не переписываются задним числом.
