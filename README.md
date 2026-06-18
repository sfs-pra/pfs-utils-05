# pfs-utils

**A toolkit for building, merging, extracting, and hot-loading squashfs/erofs
`.pfs` modules on any frugal / live-CD Linux.**

pfs-utils v5 is the runtime and build layer underneath the
[modman](https://github.com/sfs-pra/modman) module manager: it owns everything
that touches the filesystem and the kernel union — AUFS / OverlayFS mount and
unmount, format detection, module build, extraction, and private-namespace
execution.

[English](README.md) | [Русский](README.ru.md)

> **Documentation:** the full reference lives in the
> **[project wiki](https://github.com/sfs-pra/pfs-utils-05/wiki)**
> ([Русский](https://github.com/sfs-pra/pfs-utils-05/wiki/Home-ru)).

---

## What is pfs-utils

A frugal / live-CD Linux boots a read-only base assembled from squashfs `.pfs`
modules and keeps changes in a writable layer. pfs-utils is the set of scripts
that work with those modules:

- **build** `.pfs` modules from directories, images, or other modules
  (`mkpfs`, `mkpfs-erofs`);
- **attach / detach** modules to a running AUFS root without rebooting
  (`pfsload`, `pfsunload`);
- **run** an application with a module in a private namespace on any root,
  including OverlayFS (`pfsrun`, `pfsexec`);
- **install / uninstall**, **extract**, **rebuild**, **inspect**, and
  **benchmark** modules.

The utilities are **not self-contained** — they share the `pfs` function
library and are meant to be used together. Every tool has a built-in `--help`.

---

## Module model

A **module** is a squashfs (or **erofs**) archive holding a directory tree
rooted at `/`; you do not unpack the whole archive to read one file. A **PFS
module** is one built by `mkpfs`/`mkpfs-erofs` and carries metadata
(`pfs.files`, `pfs.specs`, `pfs.depends`).

- **simple** module — built from one source.
- **composite** module (container) — built from several sources; can be split
  back into its parts.

Version 5 builds on the 4.x line (keeping option-level compatibility) and adds
**OverlayFS** and **erofs** alongside the classic **AUFS** + **squashfs**.

---

## Tools

| Tool | Role |
| --- | --- |
| `pfs` | Function library; source it or call `pfs <function>`. |
| `mkpfs` / `mkpfs-erofs` | Build squashfs / erofs `.pfs` modules. |
| `pfsload` / `pfsunload` | AUFS-only hot attach / detach to the system root. |
| `pfsrun` / `pfsexec` | Run a command/app with modules in a private overlay namespace (any root). |
| `pfsextract` | Split a composite module / unpack a simple one. |
| `pfsinfo` | List modules (composite or system-wide); `--machine` TSV for tools/GUIs. |
| `pfsrebuild` | Rebuild a module from the files of an attached AUFS module. |
| `pfsuninstall` / `pfsmigrate-install` | Remove installed modules / migrate v4 metadata to v5. |
| `pfsfind` / `pfsfindlibs` / `pfsdepends` | Locate a file's owning module / find missing ELF libs / show dependencies. |
| `pfsbench` | Benchmark attach/detach and squashfs vs erofs vs RAM I/O. |
| `pfsactivate` / `pfsdeactivate` | Experimental symlink-injection activation (any rootfs). |
| `chroot2pfs` / `trim-chroot` | Build a module by working inside a chroot/nspawn; trim junk before packing. |
| `selftest` | Integrity check of the whole pipeline (run as root in a live env). |

Legacy v4 siblings (`pfs1`, `pfs-v4`, `pfsload-v4`, `pfsunload-v4`) are kept for
backward compatibility only.

---

## AUFS vs. OverlayFS

AUFS can add a layer to a **live** root (`mount -o remount,append:`), so
`pfsload`/`pfsunload` hot-attach modules system-wide. OverlayFS **cannot** add
a `lowerdir` to an active mount, so on overlay-root systems use `pfsrun` to run
an app with a module in a private namespace instead. Full survey:
[AUFS-alternatives in the wiki](https://github.com/sfs-pra/pfs-utils-05/wiki/aufs-alternatives)
([Русский](https://github.com/sfs-pra/pfs-utils-05/wiki/aufs-alternatives-ru)).

---

## Installation

```bash
# Release build from the working tree:
makepkg -si

# Or build straight from git:
makepkg -p PKGBUILD.git -si
```

This installs the `pfs-utils5` package.

---

## Usage

```bash
# Build a module from the current directory
mkpfs

# Attach / detach on an AUFS root
sudo pfsload firefox.pfs
sudo pfsunload firefox.pfs

# Run an app with a module on any root (private namespace)
sudo pfsrun firefox.pfs

# Inspect modules (machine-readable TSV for tools/GUIs)
pfsinfo --machine

# Build inside a chroot, then pack into a module/dir
chroot2pfs -o ModuleDIR --flist /tmp/module.list --command apt install mc
```

---

## Dependencies

- `bash`, `coreutils`, `findutils`, `file`, `gawk`, `grep`, `util-linux`
- `squashfs-tools` (squashfs); `erofs-utils` (optional, erofs)
- `aufs` and/or `overlayfs` kernel support
- For a GUI: [modman](https://github.com/sfs-pra/modman) — the native GTK3
  frontend that drives pfs-utils through the `pfsinfo --machine` TSV protocol.

---

## Documentation

- **[Project wiki](https://github.com/sfs-pra/pfs-utils-05/wiki)** — full
  per-tool reference (English) /
  [Русский](https://github.com/sfs-pra/pfs-utils-05/wiki/Home-ru)
- Man pages: `pfs-utils(8)` and per-tool pages under `usr/share/man/`
- [modman](https://github.com/sfs-pra/modman) — the module-manager frontend

---

## License

[GPL](https://www.gnu.org/licenses/gpl-3.0.html).
