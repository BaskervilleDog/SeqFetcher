# Sourced at the top of every *.bats file with `load 'test_helper'`.
#
# Mirrors the exact sourcing seqfetcher.sh does (same files, same order) so
# tests exercise the real function definitions, not a re-implementation.
# The one addition is a stub show_help() - the real one lives in
# seqfetcher.sh itself (the entry point, not lib/), and lib/parsers/*.sh
# call it on `--help`/`-h`/unknown-option; tests that reach that branch
# need *something* bound to the name.
show_help() { echo "HELP"; }

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/config.sh"
source "$BASE_DIR/lib/logging.sh"
source "$BASE_DIR/lib/validation.sh"
source "$BASE_DIR/lib/manifest.sh"

for file in "$BASE_DIR"/lib/commands/*.sh; do
    source "$file"
done
for file in "$BASE_DIR"/lib/parsers/*.sh; do
    source "$file"
done
for file in "$BASE_DIR"/lib/validators/*.sh; do
    source "$file"
done
for file in "$BASE_DIR"/lib/downloaders/*.sh; do
    source "$file"
done

# Re-source config.sh before each test so global option variables
# (ORGANISM, ACCESSION, DOWNLOAD_TYPE, ...) reset to their defaults instead
# of leaking state from the previous test.
reset_config() {
    source "$BASE_DIR/lib/config.sh"
}
