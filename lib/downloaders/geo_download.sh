#!/usr/bin/env bash

# GEO Download Module
# Functions for downloading GEO supplementary files and extracting SRR lists

#==============================================================
# Helper Functions
#==============================================================

retry_command() {
    local max_attempts=3
    local attempt=1
    
    while (( attempt <= max_attempts )); do
        if "$@"; then
            return 0
        fi
        log_warning "Attempt $attempt failed, retrying..."
        ((attempt++))
        sleep 2
    done
    
    return 1
}

validate_geo_accession() {
    local accession="$1"
    
    if [[ -z "$accession" ]]; then
        log_error "GEO accession cannot be empty"
        return 1
    fi
    
    # Validate GEO accession format (GSE followed by numbers)
    if [[ ! "$accession" =~ ^GSE[0-9]+$ ]]; then
        log_error "Invalid GEO accession format: $accession"
        log_error "Expected format: GSEXXXXX (e.g., GSE280953)"
        return 1
    fi
    
    return 0
}

#==============================================================
# GEO Help Functions
#==============================================================

geo_help_download_supplementary() {
    cat <<EOF
Usage:
  seqfetcher download [options]

Options:
  --geo <GSEXXXXX>      GEO series accession
  --outdir DIR          Output directory (default: downloads)
  --help               Show this help

Example:
  seqfetcher download --geo GSE280953
  seqfetcher download --geo GSE280953 --outdir geo_data
EOF
}

geo_help_create_srr() {
    cat <<EOF
Usage:
  seqfetcher geo-srr [options]

Options:
  --geo <GSEXXXXX>      GEO series accession
  --out <file>         Output file (default: SRR_list.txt)
  --outdir DIR         Output directory (default: downloads)
  --help               Show this help

Example:
  seqfetcher geo-srr --geo GSE280953 --out runs.txt
  seqfetcher geo-srr --geo GSE280953 --outdir geo_data
EOF
}

#==============================================================
# GEO Download Functions
#==============================================================

download_geo_supplementary() {
    is_help "$1" && { geo_help_download_supplementary; return 0; }
    
    local geo_accession=""
    local output_dir="${OUTPUT_DIR:-downloads}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --geo)
                geo_accession="$2"; shift 2 ;;
            --outdir)
                output_dir="$2"; shift 2 ;;
            --help|-h)
                geo_help_download_supplementary; return 0 ;;
            *)
                log_error "Unknown option: $1"
                geo_help_download_supplementary
                return 1
                ;;
        esac
    done
    
    log_step "Downloading GEO Supplementary Files"
    
    if ! validate_geo_accession "$geo_accession"; then
        return 1
    fi
    
    log_info "Downloading supplementary files for $geo_accession..."
    
    # Convert GSE123456789 -> GSE123456nnn
    local series_stub=$(echo "$geo_accession" | sed 's/\(GSE[0-9]*\)[0-9]\{3\}$/\1nnn/')
    local ftp_base="https://ftp.ncbi.nlm.nih.gov/geo/series/${series_stub}/${geo_accession}/suppl/"
    
    # Create output directories
    mkdir -p "${output_dir}/metadata/${geo_accession}"
    mkdir -p "${TEMP_DIR}"
    
    # Fetch file listing from FTP
    if ! wget -q -O "${TEMP_DIR}/file_list.html" "$ftp_base"; then
        log_error "Could not access GEO FTP site at: $ftp_base"
        log_error "Please verify the GEO accession is correct"
        return 1
    fi
    
    local file_count=0
    
    # Parse HTML and download each file
    while IFS= read -r filename; do
        [[ -z "$filename" ]] && continue
        
        # Skip non-data files (HTML pages, policy links, etc.)
        if [[ "$filename" =~ ^https?:// ]] || \
           [[ "$filename" =~ \.html?$ ]] || \
           [[ "$filename" =~ vulnerability|policy|index\.html ]]; then
            continue
        fi
        
        log_info "  Downloading: $filename"
        
        if retry_command wget -c -q --show-progress \
            -P "${output_dir}/metadata/${geo_accession}" \
            "${ftp_base}${filename}"; then
            ((file_count++))
        else
            log_warning "  Failed: $filename"
        fi
    done < <(grep -o 'href="[^"]*"' "${TEMP_DIR}/file_list.html" | \
        sed 's/href="//;s/"$//' | \
        grep -v '^\.\.' | \
        grep -v '^/')
    
    # Clean up the file list
    rm -f "${TEMP_DIR}/file_list.html"
    
    if (( file_count == 0 )); then
        log_warning "No supplementary files found for $geo_accession"
        return 1
    fi
    
    log_info "✓ Downloaded $file_count file(s)"
    log_info "Files saved to: ${output_dir}/metadata/${geo_accession}/"
}

create_srr_list_from_geo() {
    is_help "$1" && { geo_help_create_srr; return 0; }

    local geo_accession=""
    local output_file="GEO_SRR_list.txt"
    local output_dir="${OUTPUT_DIR:-downloads}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --geo)     geo_accession="$2"; shift 2 ;;
            --out)     output_file="$2";   shift 2 ;;
            --outdir)  output_dir="$2";    shift 2 ;;
            --help|-h) geo_help_create_srr; return 0 ;;
            *)
                log_error "Unknown option: $1"
                geo_help_create_srr
                return 1
                ;;
        esac
    done

    log_step "Creating SRR list from GEO accession"

    check_command curl    || return 1
    check_command python3 || return 1
    validate_geo_accession "$geo_accession" || return 1

    mkdir -p "${TEMP_DIR}"

    local soft_file="${TEMP_DIR}/${geo_accession}.soft.gz"
    local runinfo_raw="${TEMP_DIR}/runinfo_raw.csv"
    local srr_file="${TEMP_DIR}/srr.txt"
    local meta_file="${TEMP_DIR}/metadata.tsv"

    local series_prefix
    series_prefix=$(echo "$geo_accession" | sed 's/\(GSE[0-9]*\)[0-9]\{3\}$/\1nnn/')

    # ----------------------------------------------------------
    # STEP 1: Download GEO SOFT
    # ----------------------------------------------------------
    log_info "Downloading GEO SOFT metadata..."

    local soft_url="https://ftp.ncbi.nlm.nih.gov/geo/series/${series_prefix}/${geo_accession}/soft/${geo_accession}_family.soft.gz"

    if ! curl -sSf -o "$soft_file" "$soft_url"; then
        log_error "Failed to download GEO SOFT from: $soft_url"
        return 1
    fi

    # ----------------------------------------------------------
    # STEP 2: Parse SOFT → per-GSM metadata + SRX/SRR links
    #
    # Relevant SOFT fields per ^SAMPLE block:
    #   !Sample_geo_accession          → GSM id
    #   !Sample_organism_ch1           → organism
    #   !Sample_source_name_ch1        → tissue / source
    #   !Sample_characteristics_ch1    → key: value pairs (tissue, treatment, cell type…)
    #                                    may appear multiple times per sample
    #   !Sample_library_strategy       → RNA-Seq, ChIP-Seq, etc.
    #   !Sample_instrument_model       → sequencer
    #   !Sample_relation               → SRA: https://…/SRX…  or
    #                                    BioProject: https://…/PRJNA…
    # ----------------------------------------------------------
    log_info "Parsing SOFT file for sample metadata..."

    python3 - "$soft_file" "$srr_file" "$meta_file" <<'PYEOF'
import sys, gzip, re, csv, urllib.request, json, time

soft_path, srr_path, meta_path = sys.argv[1], sys.argv[2], sys.argv[3]

META_HEADER = [
    "run", "gsm", "title", "organism", "source_name",
    "tissue", "treatment", "cell_type", "characteristics",
    "library_strategy", "library_layout", "instrument", "spots"
]

# ---- smart opener: try gzip first, fall back to plain text ----
def open_soft(path):
    try:
        fh = gzip.open(path, "rt", errors="replace")
        fh.read(1)          # probe — raises if not gzip
        fh.seek(0)
        return fh
    except Exception:
        return open(path, "rt", errors="replace")

# ---- parse SOFT into per-GSM dicts ----
samples = {}
current = None

with open_soft(soft_path) as fh:
    for raw in fh:
        line = raw.rstrip("\n")

        if line.startswith("^SAMPLE"):
            gsm = line.split("=", 1)[1].strip()
            current = {
                "gsm": gsm, "title": "", "organism": "", "source_name": "",
                "characteristics": [],
                "library_strategy": "", "library_layout": "", "instrument": "",
                "srx": [], "srr": [],
            }
            samples[gsm] = current
            continue

        if current is None:
            continue

        if line.startswith("!Sample_title"):
            current["title"] = line.split("=", 1)[1].strip()
        elif line.startswith("!Sample_organism_ch1"):
            current["organism"] = line.split("=", 1)[1].strip()
        elif line.startswith("!Sample_source_name_ch1"):
            current["source_name"] = line.split("=", 1)[1].strip()
        elif line.startswith("!Sample_characteristics_ch1"):
            current["characteristics"].append(line.split("=", 1)[1].strip())
        elif line.startswith("!Sample_library_strategy"):
            current["library_strategy"] = line.split("=", 1)[1].strip()
        elif line.startswith("!Sample_instrument_model"):
            current["instrument"] = line.split("=", 1)[1].strip()
        elif line.startswith("!Sample_relation"):
            val = line.split("=", 1)[1].strip()
            srx_m = re.search(r'(SRX\d+)', val)
            srr_m = re.search(r'(SRR\d+|ERR\d+|DRR\d+)', val)
            if srx_m: current["srx"].append(srx_m.group(1))
            if srr_m: current["srr"].append(srr_m.group(1))


# ---- parse_characteristics ----
def parse_characteristics(chars):
    tissue, treatment, cell_type = "", "", ""
    for c in chars:
        if ":" not in c:
            continue
        key, _, val = c.partition(":")
        key = key.strip().lower()
        val = val.strip()
        if key in ("tissue", "tissue type", "organ"):
            tissue = val
        elif key in ("treatment", "treatment group", "condition", "genotype/variation"):
            treatment = val
        elif key in ("cell type", "cell_type", "cell line", "cell_line"):
            cell_type = val
    return tissue, treatment, cell_type


# ---- resolve SRX → SRR via NCBI efetch ----
def fetch_srr_for_srx(srx_list):
    if not srx_list:
        return []
    uid_query = "+OR+".join(srx_list)
    search_url = (
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
        f"?db=sra&term={uid_query}&retmax=500&retmode=json"
    )
    try:
        with urllib.request.urlopen(search_url, timeout=15) as r:
            data = json.loads(r.read())
        uids = data.get("esearchresult", {}).get("idlist", [])
    except Exception:
        return []
    if not uids:
        return []
    time.sleep(0.34)
    fetch_url = (
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
        f"?db=sra&id={','.join(uids)}&rettype=runinfo&retmode=text"
    )
    try:
        with urllib.request.urlopen(fetch_url, timeout=15) as r:
            text = r.read().decode("utf-8", errors="replace")
    except Exception:
        return []
    results = []
    reader = csv.DictReader(text.splitlines())
    for row in reader:
        run = row.get("Run", "").strip()
        if run and re.match(r'^(SRR|ERR|DRR)\d+$', run):
            results.append((run, row.get("spots", ""), row.get("LibraryLayout", "")))
    return results


# ---- build output rows ----
all_srr = []
meta_rows = []

for gsm, s in samples.items():
    tissue, treatment, cell_type = parse_characteristics(s["characteristics"])
    if not tissue:
        tissue = s["source_name"]

    # Join all characteristics into one readable string for the TSV column
    chars_str = " | ".join(s["characteristics"])

    run_infos = []
    if s["srr"]:
        run_infos = [(r, "", "") for r in s["srr"]]
    elif s["srx"]:
        run_infos = fetch_srr_for_srx(s["srx"])

    for (run, spots, layout) in run_infos:
        all_srr.append(run)
        meta_rows.append({
            "run":              run,
            "gsm":              gsm,
            "title":            s["title"],
            "organism":         s["organism"],
            "source_name":      s["source_name"],
            "tissue":           tissue,
            "treatment":        treatment,
            "cell_type":        cell_type,
            "characteristics":  chars_str,
            "library_strategy": s["library_strategy"],
            "library_layout":   layout or s["library_layout"],
            "instrument":       s["instrument"],
            "spots":            spots,
        })

# ---- write outputs ----
with open(srr_path, "w") as f:
    f.write("\n".join(all_srr) + "\n")

with open(meta_path, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=META_HEADER, delimiter="\t")
    writer.writeheader()
    writer.writerows(meta_rows)

print(f"Parsed {len(samples)} GSM samples, {len(all_srr)} runs")
PYEOF

    # ----------------------------------------------------------
    # FALLBACK: if SOFT had no SRX/SRR links, use old Model A/B/C
    # ----------------------------------------------------------
    if [[ ! -s "$srr_file" ]]; then
        log_warning "SOFT contained no SRA links — falling back to Entrez esearch..."

        > "$runinfo_raw"

        local sra_uids
        sra_uids=$(curl -sS \
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=sra&term=${geo_accession}&retmax=10000&retmode=json" \
            | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('\n'.join(data.get('esearchresult',{}).get('idlist',[])))
" 2>/dev/null)

        if [[ -n "$sra_uids" ]]; then
            local uid_str
            uid_str=$(echo "$sra_uids" | paste -sd ',')
            curl -sS \
                "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=sra&id=${uid_str}&rettype=runinfo&retmode=text" \
                >> "$runinfo_raw"
        fi

        # Parse runinfo → srr_file, and write a partial metadata TSV
        # (spots + layout available; tissue/treatment will be empty)
        python3 - "$runinfo_raw" "$srr_file" "$meta_file" <<'PYEOF'
import sys, csv, re

runinfo_path, srr_path, meta_path = sys.argv[1], sys.argv[2], sys.argv[3]

META_HEADER = [
    "run", "gsm", "organism", "source_name",
    "tissue", "treatment", "cell_type",
    "library_strategy", "library_layout", "instrument", "spots"
]

seen = set()
srr_lines, meta_rows = [], []

with open(runinfo_path) as fh:
    block = []
    def flush(block):
        reader = csv.DictReader(block)
        for row in reader:
            run = row.get("Run","").strip()
            if not run or not re.match(r'^(SRR|ERR|DRR)\d+$', run):
                continue
            if run in seen:
                continue
            seen.add(run)
            srr_lines.append(run)
            meta_rows.append({
                "run":              run,
                "gsm":              row.get("SampleName",""),
                "organism":         row.get("ScientificName",""),
                "source_name":      row.get("source_name",""),
                "tissue":           "",
                "treatment":        "",
                "cell_type":        "",
                "library_strategy": row.get("LibraryStrategy",""),
                "library_layout":   row.get("LibraryLayout",""),
                "instrument":       row.get("Model",""),
                "spots":            row.get("spots",""),
            })
    for raw in fh:
        line = raw.rstrip("\n")
        if line.strip() == "":
            if block:
                flush(block)
                block = []
        else:
            block.append(line)
    if block:
        flush(block)

with open(srr_path, "w") as f:
    f.write("\n".join(srr_lines) + "\n")

with open(meta_path, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=META_HEADER, delimiter="\t")
    writer.writeheader()
    writer.writerows(meta_rows)
PYEOF
    fi

    # ----------------------------------------------------------
    # VALIDATION & OUTPUT
    # ----------------------------------------------------------
    if [[ ! -s "$srr_file" ]]; then
        log_error "No SRR/ERR/DRR accessions found for ${geo_accession}"
        log_error "Dataset may be embargoed or not SRA-linked"
        rm -f "$soft_file" "$runinfo_raw" "$srr_file" "$meta_file"
        return 1
    fi

    if [[ "$output_file" != /* ]] && [[ "$output_file" != ./* ]]; then
        output_file="${output_dir}/${output_file}"
    fi

    local meta_out="${output_file%.txt}_metadata.tsv"

    mkdir -p "$(dirname "$output_file")"
    cp "$srr_file" "$output_file"
    cp "$meta_file" "$meta_out"

    log_info "✓ Found $(wc -l < "$output_file") SRR/ERR/DRR accession(s)"
    log_info "Saved run list : $output_file"
    log_info "Saved metadata : $meta_out"

    rm -f "$soft_file" "$runinfo_raw" "$srr_file" "$meta_file"
}
