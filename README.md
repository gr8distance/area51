# area51

Common Lisp package manager.

```bash
area51 new my-app
cd my-app
area51 add split-sequence --github sharplispers/split-sequence
area51 install
area51 run
```

## Install

Requires [SBCL](http://www.sbcl.org/).

```bash
git clone https://github.com/gr8distance/area51.git
cd area51
sbcl --non-interactive --load build.lisp
cp bin/area51 /usr/local/bin/  # or anywhere on your PATH
```

## Commands

| Command | Description |
|---|---|
| `area51 new <name>` | Create a new project |
| `area51 add <pkg> [options]` | Add a dependency |
| `area51 remove <pkg>` | Remove a dependency |
| `area51 install` | Install all dependencies |
| `area51 build` | Build standalone binary |
| `area51 test` | Run tests |
| `area51 run` | Run the project |

### Adding dependencies

```bash
area51 add alexandria --github sharplispers/alexandria
area51 add cl-json --url https://github.com/sharplispers/cl-json
area51 add some-lib --github user/repo --ref v1.0
```

## area51.lisp

Project configuration is a Lisp DSL:

```lisp
(project "my-app"
  :version "0.1.0"
  :license "MIT"
  :entry-point "main")

(dep "split-sequence" :github "sharplispers/split-sequence")
(dep "cl-json" :github "sharplispers/cl-json" :ref "v0.6.0")

(group (:dev :test)
  (dep "fiveam" :github "lispci/fiveam"))
```

### Install with group filtering

```bash
area51 install                # all dependencies
area51 install --production   # ungrouped + :production only
```

## How it works

- **area51.lisp** declares dependencies with source locations
- **area51.lock** pins exact git SHAs for reproducible builds
- Packages are cached globally in `~/.area51/packages/`
- Transitive dependencies are resolved by parsing `.asd` files
- `.asd` `:depends-on` is auto-updated on `add`/`remove`
- Built on ASDF (build system) with no external dependencies

## Switching Lisp implementations

```bash
AREA51_LISP=ccl area51 run   # use Clozure CL instead of SBCL
```

## License

MIT
