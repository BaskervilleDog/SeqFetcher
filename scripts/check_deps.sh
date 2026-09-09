#!/usr/bin/env bash
# SeqFetcher has no package manager and no lockfile, so this script plays
# that role instead: it checks that the interpreter and every external CLI
# tool the codebase actually shells out to (per `lib/**/*.sh`) is on PATH,
# and reports which are required vs. optional (with a note on what happens
# if each optional one is missing).
#
# Run on a new machine before using seqfetcher:
#
#   bash scripts/check_deps.sh

set -uo pipefail

ok=0
missing_required=0

check() {
    local name="$1" required="$2" note="$3"
    if command -v "$name" >/dev/null 2>&1; then
        printf '  [x] %-20s %s\n' "$name" "$(command -v "$name")"
        ok=$((ok + 1))
    elif [[ "$required" == "required" ]]; then
        printf '  [ ] %-20s MISSING (required) - %s\n' "$name" "$note"
        missing_required=$((missing_required + 1))
    else
        printf '  [ ] %-20s missing (optional) - %s\n' "$name" "$note"
    fi
}

echo "bash: $BASH_VERSION"
if (( BASH_VERSINFO[0] < 4 )); then
    echo "  warning: bash >= 4 recommended"
fi

echo "required (core search/download commands won't run without these):"
check datasets required "NCBI assembly/gene search & download - install: https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/"
check jq       required "JSON parsing throughout lib/downloaders/ - install: brew install jq / apt-get install jq"
check parallel required "GNU Parallel, used for concurrent downloads - install: brew install parallel / apt-get install parallel"
check curl     required "HTTP downloads (GEO, BioProject, Ensembl) - usually pre-installed"
check python3  required "JSON/XML post-processing in lib/downloaders/geo_download.sh and bioproject_download.sh"
check unzip    required "extracts .zip archives from 'datasets download' - assembly/gene/transcriptome/proteome/ortholog downloads"
check awk      required "field parsing, used throughout lib/"
check sed      required "text substitution, used throughout lib/"
check grep     required "text search, used throughout lib/"

echo "optional (graceful fallback, or only needed for one command/method):"
check flock                optional "serialises writes to seqfetcher.lock.json under parallel downloads (util-linux) - a mkdir spin-lock is used if missing"
check wget                 optional "fallback download client in lib/downloaders/ena_download.sh - curl is used if missing"
check fasterq-dump         optional "SRA Toolkit - only needed for 'download --sra-method fasterq' - install: https://github.com/ncbi/sra-tools/wiki/02.-Installing-SRA-Toolkit"
check prefetch              optional "SRA Toolkit - only needed for 'download --sra-method prefetch'"
check parallel-fastq-dump  optional "only needed for 'download --sra-method parallel' - install: pip install parallel-fastq-dump"
check bats                 optional "test runner for tests/*.bats - install: npm i -g bats / brew install bats-core / apt install bats"
check dot                  optional "renders graphs/*.svg in scripts/generate_function_graph.sh - without it, the .dot source is still written"
check shellcheck           optional "lints lib/*.sh and scripts/*.sh - install: winget install shellcheck / brew install shellcheck / apt install shellcheck"

echo
if (( missing_required > 0 )); then
    echo "$missing_required required tool(s) missing - install them before running seqfetcher."
    exit 1
fi
echo "all required tools present ($ok found)."
