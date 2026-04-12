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
| `area51 repl [--port N]` | Start a slynk server for SLY/SLIME to connect to |

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

### Using a new dependency in your code

`area51 add` updates `area51.lisp` and your `.asd` file, but it intentionally does **not** touch `src/package.lisp`. How you bring symbols into your package is a taste call, so area51 leaves it to you. You have a few idiomatic options:

**`:import-from`** — explicit, the most common style in modern CL code:

```lisp
(defpackage #:my-app
  (:use #:cl)
  (:import-from #:alexandria #:iota #:when-let)
  (:import-from #:arrows #:-> #:->>)
  (:export #:main))
```

**`:local-nicknames`** — keep symbols qualified without typing the full package name:

```lisp
(defpackage #:my-app
  (:use #:cl)
  (:local-nicknames (#:a #:alexandria))
  (:export #:main))
;; usage: (a:iota 5)
```

**`:use`** — pull every exported symbol in. Natural for DSL-ish libraries whose symbols are meant to read as syntax (`arrows`, `iterate`), but generally avoided for large utility libraries like alexandria where silent symbol conflicts can creep in as the library grows.

```lisp
(defpackage #:my-app
  (:use #:cl #:arrows)
  (:export #:main))
;; usage: (-> 3 (+ 20 30))
```

Or skip `package.lisp` entirely and use fully-qualified symbols in your code: `(alexandria:iota 5)`.

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
```

Test dependencies belong in a separate `.asd` file (e.g. `my-app-test.asd`), following the ASDF convention.

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

## Interactive development with SLY/SLIME

`area51 repl` starts a [slynk](https://github.com/joaotavora/sly) server with your project already loaded, and `*package*` dropped into the project package. Connect from Emacs with `M-x sly-connect` and you get a REPL scoped to the project — no `.sbclrc` or `.dir-locals.el` setup needed on the Emacs side.

```bash
area51 repl
# area51: loading my-app and starting slynk on port 4005
# area51: connect with M-x sly-connect RET 127.0.0.1 RET 4005 RET
# area51: Ctrl-C to stop
```

Then in Emacs: `M-x sly-connect RET 127.0.0.1 RET 4005 RET`. The REPL opens in your project's package, so you can immediately call `(main)` or any other exported function without qualifying.

- **`--port N`** picks a different port if 4005 is taken.
- **Ctrl-C** in the area51 terminal shuts down cleanly and releases the port, so an immediate restart just works.
- **Per-project isolation**: only dependencies listed in this project's `area51.lock` are visible to ASDF in the running sbcl, matching the isolation of `area51 run`. A sibling project's packages are not reachable from here.

Slynk is loaded via ASDF at startup. If it's not already findable on your machine (SLY ships it; `(ql:quickload :slynk)` also works), you'll get a one-line error instead of a hang.

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
- `.asd` `:depends-on` is auto-updated on `add`/`remove` (but `src/package.lisp` is left alone — see [Using a new dependency in your code](#using-a-new-dependency-in-your-code))
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
