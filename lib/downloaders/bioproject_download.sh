#!/usr/bin/env bash

#==============================================================
# BioProject Help
#==============================================================

downloaders_bioproject_download::bioproject_help_create_srr() {
    cat <<EOF
Usage:
  seqfetcher bp-srr [options]

Options:
  --bioproject <PRJNAXXXXXX>   BioProject accession (PRJNA, PRJEB, PRJDB)
  --out <file>                 Output file (default: SRR_list.txt)
  --outdir DIR                 Output directory (default: downloads)
  --help                       Show this help

Example:
  seqfetcher bp-srr --bioproject PRJNA1173518
  seqfetcher bp-srr --bioproject PRJNA1173518 --out runs.txt --outdir results
EOF
}

#==============================================================
# BioProject Validation
#==============================================================

downloaders_bioproject_download::validate_bioproject_accession() {
    local accession="$1"
    if [[ -z "$accession" ]]; then
        log_error "BioProject accession cannot be empty (pass --bioproject PRJNAXXXXXX)"
        return "${EX_USAGE:-2}"
    fi
    if [[ ! "$accession" =~ ^PRJ(NA|EB|DB)[0-9]+$ ]]; then
        log_error "Invalid BioProject accession format: $accession"
        log_error "Expected format: PRJNAXXXXXX, PRJEBXXXXXX, or PRJDBXXXXXX"
        return "${EX_USAGE:-2}"
    fi
    return 0
}

#==============================================================
# BioProject → SRR list + metadata
#==============================================================

downloaders_bioproject_download::create_srr_list_from_bioproject() {
    downloaders_common::is_help "$1" && { downloaders_bioproject_download::bioproject_help_create_srr; return 0; }

    local bioproject=""
    local output_file="BioProject_SRR_list.txt"
    local output_dir="${OUTPUT_DIR:-downloads}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --bioproject) bioproject="$2";    shift 2 ;;
            --out)        output_file="$2";   shift 2 ;;
            --outdir)     output_dir="$2";    shift 2 ;;
            --help|-h)    downloaders_bioproject_download::bioproject_help_create_srr; return 0 ;;
            *)
                log_error "Unknown option: $1"
                downloaders_bioproject_download::bioproject_help_create_srr
                return 1
                ;;
        esac
    done

    log_step "Creating SRR list from BioProject accession"

    downloaders_common::check_command curl    || return 1
    downloaders_common::check_command python3 || return 1
    downloaders_bioproject_download::validate_bioproject_accession "$bioproject" || return $?

    mkdir -p "${TEMP_DIR}"

    local runinfo_raw="${TEMP_DIR}/runinfo_raw.csv"
    local srr_file="${TEMP_DIR}/srr.txt"
    local meta_file="${TEMP_DIR}/metadata.tsv"

    # ----------------------------------------------------------
    # STEP 1: BioProject → SRA UIDs via esearch
    # The [bioproject] field tag works for PRJNA, PRJEB, PRJDB
    # ----------------------------------------------------------
    log_info "Querying NCBI SRA for BioProject ${bioproject}..."

    local sra_uids
    sra_uids=$(curl -sS \
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=sra&term=${bioproject}%5Bbioproject%5D&retmax=10000&retmode=json" \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
ids = data.get('esearchresult', {}).get('idlist', [])
print('\n'.join(ids))
" 2>/dev/null)

    if [[ -z "$sra_uids" ]]; then
        log_error "No SRA records found for BioProject ${bioproject}"
        log_error "Check the accession is correct and publicly released"
        return 1
    fi

    local uid_count
    uid_count=$(echo "$sra_uids" | wc -l)
    log_info "Found ${uid_count} SRA experiment(s), fetching runinfo..."

    # ----------------------------------------------------------
    # STEP 2: SRA UIDs → runinfo CSV
    # efetch runinfo gives us one row per RUN (not per experiment),
    # so a multi-run experiment gives multiple rows automatically.
    # ----------------------------------------------------------
    local uid_str
    uid_str=$(echo "$sra_uids" | paste -sd ',')

    curl -sS \
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=sra&id=${uid_str}&rettype=runinfo&retmode=text" \
        > "$runinfo_raw"

    if [[ ! -s "$runinfo_raw" ]]; then
        log_error "Failed to fetch runinfo from NCBI"
        return 1
    fi

    # ----------------------------------------------------------
    # STEP 3: Parse runinfo → SRR list + metadata TSV
    #
    # SRA runinfo columns we use:
    #   Run             → run accession (SRR/ERR/DRR)
    #   SampleName      → GSM or sample name
    #   BioSample       → SAMN accession
    #   Experiment      → SRX accession
    #   SRAStudy        → SRP accession
    #   BioProject      → PRJNA accession
    #   ScientificName  → organism
    #   LibraryStrategy → RNA-Seq, ChIP-Seq, etc.
    #   LibraryLayout   → PAIRED / SINGLE
    #   Model           → instrument model
    #   spots           → read count
    #   source_name     → tissue / sample description  (from biosample attributes)
    #   tissue          → tissue (sometimes present)
    #   treatment       → treatment (sometimes present)
    #   cell_type       → cell type (sometimes present)
    #
    # Note: source_name / tissue / treatment / cell_type appear as extra
    # columns that SRA appends from BioSample attributes — their presence
    # varies by submission. We extract all of them plus dump every
    # non-standard column into a "characteristics" catch-all.
    # ----------------------------------------------------------
    log_info "Parsing runinfo..."

    python3 - "$runinfo_raw" "$srr_file" "$meta_file" <<'PYEOF'
import sys, csv, re

runinfo_path, srr_path, meta_path = sys.argv[1], sys.argv[2], sys.argv[3]

FIXED = [
    "run", "experiment", "biosample", "bioproject",
    "gsm", "organism",
    "source_name", "tissue", "treatment", "cell_type",
    "library_strategy", "library_layout", "instrument", "spots",
]

RENAME = {
    "Run":             "run",
    "Experiment":      "experiment",
    "BioSample":       "biosample",
    "BioProject":      "bioproject",
    "SampleName":      "gsm",
    "ScientificName":  "organism",
    "LibraryStrategy": "library_strategy",
    "LibraryLayout":   "library_layout",
    "Model":           "instrument",
    "spots":           "spots",
}

BIOSAMPLE_FIELDS = {
    "source_name": ["source_name", "tissue", "source name"],
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

    bs_map = {
        field: find_biosample_col(headers, candidates)
        for field, candidates in BIOSAMPLE_FIELDS.items()
    }

    known = set(RENAME.keys()) | {
        c for cand in BIOSAMPLE_FIELDS.values() for c in cand
    }

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
    block_lines = []

    for raw in fh:
        line = raw.rstrip("\n")

        if line.strip() == "":
            flush_block(block_lines)
            block_lines = []
        else:
            block_lines.append(line)

    flush_block(block_lines)


final_header = FIXED + [c for c in extra_cols if c not in FIXED]

with open(srr_path, "w") as f:
    f.write("\n".join(srr_lines) + "\n")

with open(meta_path, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=final_header,
        delimiter="\t",
        extrasaction="ignore"
    )
    writer.writeheader()
    writer.writerows(meta_rows)

print(f"Parsed {len(srr_lines)} runs")
PYEOF

    # ----------------------------------------------------------
    # VALIDATION & OUTPUT
    # ----------------------------------------------------------
    if [[ ! -s "$srr_file" ]]; then
        log_error "No SRR/ERR/DRR accessions found for ${bioproject}"
        rm -f "$runinfo_raw" "$srr_file" "$meta_file"
        return 1
    fi

    if [[ "$output_file" != /* ]] && [[ "$output_file" != ./* ]]; then
        # A list of SRR accessions + its metadata TSV, not sequence data -
        # keep it out of output_dir's root alongside downloaded files.
        output_file="${output_dir}/tables/${output_file}"
    fi

    local meta_out="${output_file%.txt}_metadata.tsv"

    mkdir -p "$(dirname "$output_file")"
    cp "$srr_file" "$output_file"
    cp "$meta_file" "$meta_out"

    # Expose resolved paths so commands_bioproject_srr::emit_json can report them.
    BP_SRR_OUT="$output_file"
    BP_SRR_META="$meta_out"

    log_info "✓ Found $(wc -l < "$output_file") SRR/ERR/DRR accession(s)"
    log_info "Saved run list : $output_file"
    log_info "Saved metadata : $meta_out"

    rm -f "$runinfo_raw" "$srr_file" "$meta_file"
}