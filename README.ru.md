# pfs-utils

**Набор утилит для сборки, слияния, извлечения и горячего подключения
squashfs/erofs `.pfs`-модулей на любом frugal / live-CD Linux.**

pfs-utils v5 — runtime- и сборочный слой под менеджером модулей
[modman](https://github.com/sfs-pra/modman): он владеет всем, что касается
файловой системы и kernel union — mount/unmount AUFS / OverlayFS, детект
формата, сборка, извлечение и запуск в приватном namespace.

[English](README.md) | [Русский](README.ru.md)

> **Документация:** полная справка — в
> **[вики проекта](https://github.com/sfs-pra/pfs-utils-05/wiki/Home-ru)**
> ([English](https://github.com/sfs-pra/pfs-utils-05/wiki)).

---

## Что такое pfs-utils

Frugal / live-CD Linux загружает read-only базу, собранную из squashfs
`.pfs`-модулей, и хранит изменения в записываемом слое. pfs-utils — набор
скриптов для работы с этими модулями:

- **сборка** `.pfs`-модулей из каталогов, образов или других модулей
  (`mkpfs`, `mkpfs-erofs`);
- **подключение / отключение** модулей к живому AUFS-корню без перезагрузки
  (`pfsload`, `pfsunload`);
- **запуск** приложения с модулем в приватном namespace на любом корне,
  включая OverlayFS (`pfsrun`, `pfsexec`);
- **инсталляция / деинсталляция**, **извлечение**, **пересборка**,
  **инспекция** и **бенчмарк** модулей.

Утилиты **не самодостаточны** — они используют общую библиотеку функций `pfs`
и предназначены для совместной работы. У каждой есть встроенный `--help`.

---

## Модель модуля

**Модуль** — squashfs- (или **erofs**) архив с деревом каталогов от корня `/`;
чтобы прочитать один файл, не нужно распаковывать весь архив. **PFS-модуль** —
собранный через `mkpfs`/`mkpfs-erofs`, несёт метаданные (`pfs.files`,
`pfs.specs`, `pfs.depends`).

- **простой** модуль — собран из одного источника.
- **составной** модуль (контейнер) — собран из нескольких источников; может
  быть разобран обратно на составляющие.

Версия 5 развивает линейку 4.x (сохраняя совместимость по ключам) и добавляет
**OverlayFS** и **erofs** наряду с классическими **AUFS** + **squashfs**.

---

## Утилиты

| Утилита | Роль |
| --- | --- |
| `pfs` | Библиотека функций; подключите через source или вызывайте `pfs <function>`. |
| `mkpfs` / `mkpfs-erofs` | Сборка squashfs / erofs `.pfs`-модулей. |
| `pfsload` / `pfsunload` | Только AUFS: горячее подключение / отключение к корню системы. |
| `pfsrun` / `pfsexec` | Запуск команды/приложения с модулями в приватном overlay namespace (любой корень). |
| `pfsextract` | Разбор составного модуля / распаковка простого. |
| `pfsinfo` | Список модулей (составной или вся система); `--machine` — TSV для скриптов/GUI. |
| `pfsrebuild` | Пересборка модуля по файлам уже подключённого AUFS-модуля. |
| `pfsuninstall` / `pfsmigrate-install` | Удаление установленных модулей / миграция метаданных v4 → v5. |
| `pfsfind` / `pfsfindlibs` / `pfsdepends` | Поиск модуля-владельца файла / поиск отсутствующих ELF-libs / показ зависимостей. |
| `pfsbench` | Бенчмарк подключения/отключения и I/O squashfs vs erofs vs RAM. |
| `pfsactivate` / `pfsdeactivate` | Экспериментальная активация через symlink-инъекцию (любой rootfs). |
| `chroot2pfs` / `trim-chroot` | Сборка модуля внутри chroot/nspawn; очистка лишнего перед упаковкой. |
| `selftest` | Проверка целостности всего пайплайна (от root в live-среде). |

Legacy v4-siblings (`pfs1`, `pfs-v4`, `pfsload-v4`, `pfsunload-v4`) сохранены
только для обратной совместимости.

---

## AUFS против OverlayFS

AUFS умеет добавлять слой к **живому** корню (`mount -o remount,append:`),
поэтому `pfsload`/`pfsunload` подключают модули системно. OverlayFS **не может**
добавить `lowerdir` к активному mount — на overlay-root системах используйте
`pfsrun`, чтобы запустить приложение с модулем в приватном namespace. Полный
обзор:
[AUFS-альтернативы в вики](https://github.com/sfs-pra/pfs-utils-05/wiki/aufs-alternatives-ru)
([English](https://github.com/sfs-pra/pfs-utils-05/wiki/aufs-alternatives)).

---

## Установка

```bash
# Релизная сборка из рабочего дерева:
makepkg -si

# Либо сборка прямо из git:
makepkg -p PKGBUILD.git -si
```

Устанавливается пакет `pfs-utils-cli`.

---

## Использование

```bash
# Собрать модуль из текущего каталога
mkpfs

# Подключить / отключить на AUFS-корне
sudo pfsload firefox.pfs
sudo pfsunload firefox.pfs

# Запустить приложение с модулем на любом корне (приватный namespace)
sudo pfsrun firefox.pfs

# Инспекция модулей (машиночитаемый TSV для скриптов/GUI)
pfsinfo --machine

# Сборка внутри chroot, затем упаковка в модуль/каталог
chroot2pfs -o ModuleDIR --flist /tmp/module.list --command apt install mc
```

---

## Зависимости

- `bash`, `coreutils`, `findutils`, `file`, `gawk`, `grep`, `util-linux`
- `squashfs-tools` (squashfs); `erofs-utils` (опционально, erofs)
- поддержка `aufs` и/или `overlayfs` в ядре
- для GUI: [modman](https://github.com/sfs-pra/modman) — родной GTK3-frontend,
  который управляет pfs-utils через TSV-протокол `pfsinfo --machine`.

---

## Документация

- **[Вики проекта](https://github.com/sfs-pra/pfs-utils-05/wiki/Home-ru)** —
  полная справка по утилитам (Русский) /
  [English](https://github.com/sfs-pra/pfs-utils-05/wiki)
- Man-страницы: `pfs-utils(8)` и страницы по утилитам в `usr/share/man/`
- [modman](https://github.com/sfs-pra/modman) — frontend-менеджер модулей

---

## Лицензия

[GPL](https://www.gnu.org/licenses/gpl-3.0.html).
