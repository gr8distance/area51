# area51

A package manager for Common Lisp. Works like npm/mix/cargo — no Quicklisp setup required at runtime.

```bash
area51 new my-app
cd my-app
area51 add alexandria
area51 install
area51 run
```

## Install

Requires [SBCL](http://www.sbcl.org/) and git.

```bash
curl -fsSL https://raw.githubusercontent.com/gr8distance/area51/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/gr8distance/area51.git
cd area51
sbcl --non-interactive --load build.lisp
cp bin/area51 /usr/local/bin/  # or anywhere on your PATH
```

Set `INSTALL_DIR` to change the install location:

```bash
INSTALL_DIR=~/.local/bin curl -fsSL https://raw.githubusercontent.com/gr8distance/area51/main/install.sh | bash
```

## Commands

| Command | Description |
|---|---|
| `area51 new <name>` | Create a new project |
| `area51 add <pkg> [options]` | Add a dependency |
| `area51 remove <pkg>` | Remove a dependency |
| `area51 install` | Install all dependencies |
| `area51 list` | List dependencies |
| `area51 clean` | Clean package cache |
| `area51 build` | Build standalone binary |
| `area51 test` | Run tests |
| `area51 run` | Run the project |

### Adding dependencies

```bash
# From Quicklisp (default — no flags needed)
area51 add alexandria
area51 add cl-ppcre

# From GitHub
area51 add my-lib --github user/my-lib
area51 add cl-json --url https://github.com/sharplispers/cl-json
area51 add some-lib --github user/repo --ref v1.0
```

## area51.lisp

Project configuration as S-expressions:

```lisp
(project "my-app"
  :version "0.1.0"
  :license "MIT"
  :entry-point "main")

(deps
  ("alexandria")
  ("cl-ppcre")
  ("my-lib" :github "user/my-lib"))

(dev-deps
  ("fiveam" :github "lispci/fiveam"))
```

### Install with group filtering

```bash
area51 install                # all dependencies
area51 install --production   # deps only (no dev-deps)
```

## area51.lock

`area51 install` generates a lock file that pins exact versions for reproducible builds:

```lisp
(:dist-version "2026-01-01"
 :packages
 ((:name "alexandria"
   :path "/home/user/.area51/packages/alexandria/"
   :source :quicklisp
   :sha nil)
  (:name "cl-ppcre"
   :path "/home/user/.area51/packages/cl-ppcre/"
   :source :quicklisp
   :sha nil)
  (:name "my-lib"
   :path "/home/user/.area51/packages/my-lib/"
   :source :github
   :sha "a1b2c3d4e5f6...")))
```

Quicklisp packages are pinned to the dist version. GitHub packages are pinned to the exact commit SHA. Commit `area51.lock` to version control for reproducible builds across machines.

## Dependency resolution

area51 resolves the full dependency tree automatically:

1. Direct dependencies from `area51.lisp` are downloaded (Quicklisp or GitHub)
2. Each package's `.asd` file is parsed for `:depends-on`
3. Transitive dependencies are resolved recursively
4. If a transitive dep isn't in the cache, area51 falls back to Quicklisp automatically

This means you only need to declare your direct dependencies — area51 handles the rest.

```
my-app
 ├── cl-ppcre (declared in area51.lisp)
 │    ├── flexi-streams (auto-resolved from .asd)
 │    │    └── trivial-gray-streams (auto-resolved)
 │    └── cl-unicode (auto-resolved from .asd)
 └── alexandria (declared in area51.lisp)
```

Built-in systems (`asdf`, `uiop`, `sb-*`) are recognized and skipped. Circular dependencies are detected via the resolved set — a package is never processed twice.

## How it works

- **area51.lisp** declares dependencies (Quicklisp or GitHub)
- **area51 install** downloads packages to `~/.area51/packages/`
  - Quicklisp packages: fetched from the Quicklisp dist as tarballs
  - GitHub packages: cloned via git
- **area51.lock** pins exact versions and SHAs for reproducible builds
- `.asd` `:depends-on` is auto-updated on `add`/`remove`
- Built on ASDF — no external dependencies, no Quicklisp runtime needed

### Quicklisp integration

area51 uses Quicklisp purely as a **download source**. It fetches the dist index, downloads tarballs, and extracts them locally. At runtime, ASDF loads packages directly from the cache — `ql:quickload` is never called.

This means:
- No Quicklisp installation required
- No `.sbclrc` setup
- Dependencies are isolated per-project, not global

## Switching Lisp implementations

```bash
AREA51_LISP=ccl area51 run   # use Clozure CL instead of SBCL
```

## Contributing

Issues and pull requests are welcome! Whether it's a bug report, feature request, or code contribution, we appreciate your help.

- **Bug reports**: Please include your SBCL version, OS, and steps to reproduce
- **Feature requests**: Open an issue to discuss before implementing
- **Pull requests**: Fork the repo, create a branch, and submit a PR

If you're a Lisper with ideas on how to make CL package management better, we'd love to hear from you.

## License

MIT
