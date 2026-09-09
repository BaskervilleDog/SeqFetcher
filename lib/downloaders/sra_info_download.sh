#!/usr/bin/env bash

# SRA runinfo without downloading reads.
#
# Given any SRA-resolvable accession (SRR/ERR/DRR, SRX, SRP/ERP/DRP, or a
# BioProject PRJNA/PRJEB/PRJDB), fetch the SRA runinfo table: one row per run
# with library / instrument / spot-count / BioSample metadata. Same
# esearch(db=sra) -> efetch(rettype=runinfo) machinery that geo-srr / bp-srr
# use internally; the runinfo -> (runs.txt + metadata.tsv) parser below is the
# same shape as lib/downloaders/bioproject_download.sh's and could be factored
# into a shared helper later.

downloaders_sra_info_download::sra_info_help() {
    cat <<EOF
Usage:
  seqfetcher sra-info --accession <ACC[,ACC...]> [options]
  seqfetcher sra-info --accession-file <file> [options]

Accepts SRR/ERR/DRR, SRX, SRP/ERP/DRP and BioProject (PRJNA/PRJEB/PRJDB)
accessions - anything searchable in the NCBI SRA database.

Options:
  --accession <ACC[,ACC...]>   One or more accessions (comma-separated)
  --accession-file <file>      File with one accession per line
  --out <file>                 Run-list filename (default: sra_runinfo_runs.txt)
  --outdir <dir>               Output directory (default: downloads)
  -h, --help                   Show this help

Outputs (under <outdir>/tables/):
  sra_runinfo.tsv              full runinfo table (one row per run)
  sra_runinfo_runs.txt         run accessions only, one per line
EOF
}

downloaders_sra_info_download::create_runinfo_table() {
    downloaders_common::is_help "$1" && { downloaders_sra_info_download::sra_info_help; return 0; }

    local accessions_csv=""
    local accession_file=""
    local output_file="sra_runinfo_runs.txt"
    local output_dir="${OUTPUT_DIR:-downloads}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --accession)      accessions_csv="$2"; shift 2 ;;
            --accession-file) accession_file="$2"; shift 2 ;;
            --out)            output_file="$2";    shift 2 ;;
            --outdir)         output_dir="$2";     shift 2 ;;
            --help|-h)        downloaders_sra_info_download::sra_info_help; return 0 ;;
            *)
                log_error "Unknown option: $1"
                downloaders_sra_info_download::sra_info_help
                return "${EX_USAGE:-2}"
                ;;
        esac
    done

    log_step "Fetching SRA runinfo"

    downloaders_common::check_command curl    || return "${EX_DEPENDENCY:-3}"
    downloaders_common::check_command python3 || return "${EX_DEPENDENCY:-3}"

    # ---- gather accessions ----
    local -a accs=()
    [[ -n "$accessions_csv" ]] && IFS=',' read -ra accs <<< "$accessions_csv"
    if [[ -n "$accession_file" ]]; then
        [[ -f "$accession_file" ]] || { log_error "Accession file not found: $accession_file"; return "${EX_USAGE:-2}"; }
        mapfile -t -O "${#accs[@]}" accs < <(grep -vE '^\s*#|^\s*$' "$accession_file")
    fi
    # trim whitespace, drop empties
    local -a clean=()
    local a
    for a in "${accs[@]}"; do a="${a//[[:space:]]/}"; [[ -n "$a" ]] && clean+=("$a"); done
    accs=("${clean[@]}")

    [[ ${#accs[@]} -eq 0 ]] && { log_error "No accessions given (use --accession or --accession-file)"; return "${EX_USAGE:-2}"; }

    mkdir -p "${TEMP_DIR}"
    local runinfo_raw="${TEMP_DIR}/sra_runinfo_raw.csv"
    local srr_file="${TEMP_DIR}/sra_runs.txt"
    local meta_file="${TEMP_DIR}/sra_runinfo.tsv"

    # ---- STEP 1: accessions -> SRA UIDs via esearch ----
    local term
    term="$(printf '%s+OR+' "${accs[@]}")"; term="${term%+OR+}"
    log_info "Querying NCBI SRA for: ${accs[*]}"

    local sra_uids
    sra_uids=$(curl -sS \
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=sra&term=${term}&retmax=100000&retmode=json" \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('\n'.join(data.get('esearchresult', {}).get('idlist', [])))
" 2>/dev/null)

    if [[ -z "$sra_uids" ]]; then
        log_error "No SRA records found for: ${accs[*]}"
        log_error "Check the accession(s) are correct and publicly released"
        return "${EX_NOTFOUND:-4}"
    fi

    local uid_count
    uid_count=$(echo "$sra_uids" | wc -l)
    log_info "Found ${uid_count} SRA experiment(s), fetching runinfo..."

    # ---- STEP 2: UIDs -> runinfo CSV ----
    # POST the id list (a study can have thousands of experiments - too long
    # for an efetch GET URL, which NCBI caps around 2 KB).
    local uid_str
    uid_str=$(echo "$sra_uids" | paste -sd ',')
    curl -sS -X POST \
        --data-urlencode "db=sra" \
        --data-urlencode "rettype=runinfo" \
        --data-urlencode "retmode=text" \
        --data-urlencode "id=${uid_str}" \
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi" \
        > "$runinfo_raw"

    # runinfo CSV always starts with the "Run," header; anything else is an error page.
    if [[ ! -s "$runinfo_raw" ]] || ! head -n1 "$runinfo_raw" | grep -q '^Run,'; then
        log_error "Failed to fetch runinfo from NCBI"
        return "${EX_NETWORK:-5}"
    fi

    # ---- STEP 3: parse runinfo -> runs.txt + metadata.tsv ----
    log_info "Parsing runinfo..."
    python3 - "$runinfo_raw" "$srr_file" "$meta_file" <<'PYEOF'
import sys, csv, re

runinfo_path, srr_path, meta_path = sys.argv[1], sys.argv[2], sys.argv[3]

FIXED = [
    "run", "experiment", "biosample", "bioproject", "study",
    "gsm", "organism",
    "source_name", "tissue", "treatment", "cell_type",
    "library_strategy", "library_selection", "library_layout",
    "instrument", "platform", "spots", "bases", "size_MB",
]

RENAME = {
    "Run":              "run",
    "Experiment":       "experiment",
    "BioSample":        "biosample",
    "BioProject":       "bioproject",
    "SRAStudy":         "study",
    "SampleName":       "gsm",
    "ScientificName":   "organism",
    "LibraryStrategy":  "library_strategy",
    "LibrarySelection": "library_selection",
    "LibraryLayout":    "library_layout",
    "Model":            "instrument",
    "Platform":         "platform",
    "spots":            "spots",
    "bases":            "bases",
    "size_MB":          "size_MB",
}

BIOSAMPLE_FIELDS = {
    "source_name": ["source_name", "source name"],
    "tissue":      ["tissue", "tissue type", "organ", "tissue/cell type"],
    "treatment":   ["treatment", "treatment group", "condition", "drug treatment"],
    "cell_type":   ["cell type", "cell_type", "cell line", "cell_line",
                    "celltype", "cell-type"],
}


def find_biosample_col(headers, candidates):
    h_lower = {h.lower(): h for h in headers}
    for c in candidates:
        if c.lower() in h_lower:
            return h_lower[c.lower()]
    return None


seen = set()
srr_lines = []
meta_rows = []
extra_cols = []


def flush_block(lines):
    if not lines:
        return
    reader = csv.DictReader(lines)
    headers = reader.fieldnames or []
    bs_map = {f: find_biosample_col(headers, cs) for f, cs in BIOSAMPLE_FIELDS.items()}
    known = set(RENAME.keys()) | {c for cs in BIOSAMPLE_FIELDS.values() for c in cs}
    for h in headers:
        if h not in known and h not in extra_cols:
            extra_cols.append(h)
    for row in reader:
        run = (row.get("Run") or "").strip()
        if not run or not re.match(r'^(SRR|ERR|DRR)\d+$', run):
            continue
        if run in seen:
            continue
        seen.add(run)
        srr_lines.append(run)
        r = {f: "" for f in FIXED}
        for src, dst in RENAME.items():
            r[dst] = (row.get(src) or "").strip()
        for field, col in bs_map.items():
            if col:
                r[field] = (row.get(col) or "").strip()
        for h in extra_cols:
            r[h] = (row.get(h) or "").strip()
        meta_rows.append(r)


with open(runinfo_path) as fh:
    block = []
    for raw in fh:
        line = raw.rstrip("\n")
        if line.strip() == "":
            flush_block(block); block = []
        else:
            block.append(line)
    flush_block(block)

final_header = FIXED + [c for c in extra_cols if c not in FIXED]

with open(srr_path, "w") as f:
    f.write("\n".join(srr_lines) + "\n")

with open(meta_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=final_header, delimiter="\t", extrasaction="ignore")
    w.writeheader()
    w.writerows(meta_rows)

print(f"Parsed {len(srr_lines)} runs", file=sys.stderr)
PYEOF

    if [[ ! -s "$srr_file" ]]; then
        log_error "No SRR/ERR/DRR runs found for: ${accs[*]}"
        rm -f "$runinfo_raw" "$srr_file" "$meta_file"
        return "${EX_NOTFOUND:-4}"
    fi

    # ---- output ----
    if [[ "$output_file" != /* && "$output_file" != ./* ]]; then
        output_file="${output_dir}/tables/${output_file}"
    fi
    local meta_out="${output_dir}/tables/sra_runinfo.tsv"

    mkdir -p "$(dirname "$output_file")"
    cp "$srr_file"  "$output_file"
    cp "$meta_file" "$meta_out"

    SRA_INFO_OUT="$output_file"
    SRA_INFO_META="$meta_out"

    log_info "✓ Found $(grep -c . "$output_file") run(s)"
    log_info "Saved run list : $output_file"
    log_info "Saved runinfo  : $meta_out"

    rm -f "$runinfo_raw" "$srr_file" "$meta_file"
}
