UNDEADPEOPLE HYBRID v3 — ПОЛНЫЙ КОМПЛЕКТ
========================================

Текущая версия в CDDA-Mods: 3.1.1 (revision смотрите в manifest/package descriptor).

Поддерживаемые repository targets:
- experimental-2026-09-23-0546;
- experimental-2026-10-01-1040.

Название тайлсета в игре может по-прежнему содержать "(2026-09-23)": это имя
исторического графического baseline, а не ограничение текущего installer target.

Важное различие:
- Audit/ и REPORT_RU.md измеряют покрытие относительно baseline 2026-09-23-0546;
- текущая совместимость пакета/установщика с 1040 проверяется общей
  инфраструктурой CDDA-Mods и не означает пересчёт coverage-таблиц на реестр 1040.

Установка через общий CDDA-Mods installer:
1. распакуйте весь CDDA-Mods-Installer.zip;
2. запустите INSTALL.cmd;
3. выберите UndeadPeople или profile:all-content;
4. после установки выберите "UndeadPeople Hybrid v3 (2026-09-23)" в графических
   настройках игры.

Общий installer проверяет SHA-256, делает backup/rollback и на длинных CatLauncher
путях использует короткий TEMP staging. Сохранения тайлсет не меняет.

Лицензии и donor provenance сохранены в SOURCE_INFO*.txt, CREDITS_UDP.txt и LICENSE_*.
