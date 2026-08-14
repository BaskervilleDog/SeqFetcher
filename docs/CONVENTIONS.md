# Development Conventions

How this codebase is organized, and why - for anyone adding a command,
downloader, or test. SeqFetcher's layout is adapted from a small family of
data-analysis project templates; this doc records where it followed that
convention and where it deliberately diverged, so the divergence reads as
a decision rather than as drift.

## Folder structure

```
├── lib/
│   ├── config.sh           Global option variables and their defaults - no functions.
│   ├── logging.sh           log_info / log_error / log_warning / log_step / log_success.
│   ├── validation.sh          require_datasets, require_jq, validate_accession.
│   ├── commands/         One file per CLI subcommand - parses, validates, dispatches. No download logic of its own.
│   ├── parsers/           `--flag` parsing for each command, sets the config.sh globals.
│   ├── validators/         Checks the globals a command needs are present/valid before it runs.
│   └── downloaders/        The actual network calls (NCBI, ENA, GEO, Ensembl, SRA) and their own format validators.
├── tests/                bats-core, one *.bats file per lib/ concern
│   └── test_helper.bash    sources lib/ exactly the way seqfetcher.sh does
├── scripts/
│   ├── check_deps.sh                 preflight check for every external CLI tool lib/ shells out to
│   └── generate_function_graph.sh    regenerates graphs/ from the current code
├── graphs/               auto-generated call graph + dependency graph (committed)
├── docs/                 this file, the command reference, and troubleshooting
└── seqfetcher.sh         entry point: sources lib/, dispatches to commands/
```

`seqfetcher.sh` only sources and dispatches - it has no logic of its own,
same as `scripts/run_pipeline.sh` in a data-analysis project. Where this
project differs from a linear analysis pipeline (`io → clean → features →
model → viz`) is that it's a multi-command CLI hitting several unrelated
external APIs, so there's no single pipeline shape to orchestrate - each
`commands/*.sh` file is its own independent entry point, and there's
deliberately no `data/`, `notebooks/`, or `reports/figures/`: nothing here
produces a fixed on-disk pipeline artifact tree the way a data-analysis
template's example dataset does. A user's `--outdir` is runtime output, not
a project asset.

## Function naming: `dir_stem::function`

Every function in `lib/commands/`, `lib/parsers/`, `lib/validators/`, and
`lib/downloaders/` is named `<dir>_<file-stem>::<name>` -
`commands_search::run_search`, `validators_assembly::validate_assembly_download`,
`downloaders_ncbi_search::search_assemblies_by_organism`.

A flatter `<file-stem>::<name>` (one prefix segment, no directory) is the
more common version of this convention, and is enough when `lib/` is a
single flat directory of pipeline-stage files with unique names. It isn't
enough here: this project nests `lib/` one level deeper by *concern*
(`commands/`, `parsers/`, `validators/`, `downloaders/`), and several of
those directories reuse the same file stem for different things - e.g.
`commands/search.sh`, `parsers/search.sh`, and `validators/search.sh` all
exist side by side. `search::` alone couldn't tell those three apart, so
the directory is folded into the prefix: `commands_search::`,
`parsers_search::`, `validators_search::`.

`lib/config.sh`, `lib/logging.sh`, and `lib/validation.sh` sit directly
under `lib/` (not in a concern subdirectory) and are exempt - they're
cross-cutting utilities called from every other file, not one
command/parser/validator/downloader among peers, so `log_info`,
`validate_accession`, etc. keep their plain names. The same logic that
justifies the `dir_stem::` prefix elsewhere (avoiding collisions between
same-named files) doesn't apply to them: there's only one `logging.sh`,
so there's nothing for `log_info` to collide with.

## Tests: bats-core

Install with `npm install -g bats`, `brew install bats-core`, or
`apt install bats`. Run with:

```bash
bats tests/
```

- `tests/test_<concern>.bats` - unit tests for the matching `lib/` file(s)
- `tests/test_cli.bats` - runs the real `seqfetcher.sh` as a subprocess for
  each command, the way `test_pipeline_integration.bats` exercises a full
  pipeline in a data-analysis template - catches sourcing/dispatch
  regressions the per-file unit tests can't see
- `tests/test_helper.bash` - sources `lib/**/*.sh` exactly the way
  `seqfetcher.sh` does, plus a `show_help()` stub (the real one lives in
  `seqfetcher.sh` itself, not `lib/`)

Coverage is intentionally scoped to what's deterministic offline: argument
parsing (`lib/parsers/`), input validation (`lib/validators/` and the
accession-format checks inside `lib/downloaders/`), small pure helpers
(`lib/downloaders/common.sh`), and CLI dispatch. The functions that
actually call `curl`/`datasets`/`jq` against live APIs
(`lib/downloaders/*_download.sh`, `lib/downloaders/ncbi_search.sh`, ...)
are not unit-tested - faking their network responses convincingly would
cost more than it'd catch. Add a test alongside every new parser or
validator function; treat a new downloader function as needing manual/live
verification instead.

One pre-existing thing the test suite fixed in passing: every
`lib/validators/*.sh` function used to fall through to `return 0` only by
accident (the exit status of its last `[[ ... ]] && { ... }` guard, which
is `1` whenever the guard - correctly - doesn't fire). Harmless before,
since no caller checked the return value, but not a contract you can write
a "validation passes" test against. Each now ends with an explicit
`return 0`.

## Dependency checking: `scripts/check_deps.sh`

No package manager, no lockfile in the language-ecosystem sense -
`scripts/check_deps.sh` is what stands in for one. It checks that every
external CLI tool `lib/**/*.sh` actually shells out to (`datasets`, `jq`,
`parallel`, `curl`, `python3`, plus the SRA Toolkit / `wget` /
`parallel-fastq-dump` for the commands that need them) is on `PATH`, split
into required vs. optional. Run it first on a new machine:

```bash
bash scripts/check_deps.sh
```

`environment.yml` is the closest thing to an actual lockfile: a
conda/mamba environment that installs all of the above from
conda-forge/bioconda in one command (`conda env create -f environment.yml`),
so a fresh clone doesn't need every tool installed by hand. It's the
installation path documented first in the README.

If a real change adds a new external tool dependency, add it in **both**
places - a `check` line in `scripts/check_deps.sh` and a line in
`environment.yml` - so the two can't drift apart.

## Function-flow & dependency graphs

`scripts/generate_function_graph.sh` scans `lib/**/*.sh`, `seqfetcher.sh`,
and `scripts/*.sh` with grep/awk (bash has no `ast`/`parse()` to lean on)
and writes:

- **`graphs/call_graph.svg`** - which function calls which function
- **`graphs/dependency_graph.svg`** - which file sources which other file,
  and which external commands it invokes or checks for (dashed edges, from
  `command -v` guards)

Regenerate after structural changes:

```bash
bash scripts/generate_function_graph.sh
```

Requires the Graphviz `dot` CLI on `PATH` (`winget install graphviz` /
`brew install graphviz` / `apt install graphviz`); without it, the `.dot`
source is still written. It resolves direct calls to a known
`dir_stem::function` name and skips anything it can't confidently resolve
(dynamic dispatch such as `check_command`'s `command -v "$1"`, where the
argument is a variable) rather than guessing.

## Linting

[`shellcheck`](https://www.shellcheck.net/) - install with
`winget install shellcheck` / `brew install shellcheck` /
`apt install shellcheck`. Run:

```bash
shellcheck lib/**/*.sh scripts/*.sh seqfetcher.sh
```
