#!/usr/bin/env bash

# Protein structure download.
#   AlphaFold  - predicted models by UniProt accession, via the EBI API
#                (https://alphafold.ebi.ac.uk/api/prediction/<ACC>).
#   RCSB PDB   - experimental structures by 4-character PDB id, direct file
#                download (https://files.rcsb.org/download/<ID>.<fmt>).
# Format: pdb (default) or cif.

ALPHAFOLD_API="https://alphafold.ebi.ac.uk/api/prediction"
RCSB_FILES="https://files.rcsb.org/download"

# downloaders_structure_download::download_alphafold <uniprot> <outdir> <fmt>
downloaders_structure_download::download_alphafold() {
    local acc="$1" outdir="$2" fmt="${3:-pdb}"
    local key="${acc}:alphafold:${fmt}"

    local meta
    meta="$(curl -fsS "${ALPHAFOLD_API}/${acc}" 2>/dev/null)"
    if [[ -z "$meta" ]] || ! jq -e '.[0]' >/dev/null 2>&1 <<< "$meta"; then
        log_error "[$acc] no AlphaFold model available"
        manifest::record "$key" "$(jq -n '{uniprot:"'"$acc"'", type:"structure", source:"alphafold", status:"failed"}')"
        return "${EX_NOTFOUND:-4}"
    fi

    local url ver dest
    url="$(jq -r --arg f "$fmt" 'if $f == "cif" then .[0].cifUrl else .[0].pdbUrl end' <<< "$meta")"
    ver="$(jq -r '.[0].latestVersion // empty' <<< "$meta")"
    dest="${outdir}/structures/alphafold/$(basename "$url")"

    if downloaders_common::already_have "$dest" "$(manifest::stored_md5 "$key")"; then
        log_info "[$acc] AlphaFold model already present - skipping"
        manifest::record_run_only "$key" "$(jq -n --arg p "$dest" '{uniprot:"'"$acc"'", type:"structure", source:"alphafold", status:"skipped", files:[{path:$p}]}')"
        return 0
    fi

    local rc
    downloaders_common::atomic_fetch "$url" "$dest"; rc=$?
    if [[ $rc -ne 0 ]]; then
        manifest::record "$key" "$(jq -n '{uniprot:"'"$acc"'", type:"structure", source:"alphafold", status:"failed"}')"
        return "$rc"
    fi

    log_success "[$acc] AlphaFold model v${ver:-?} -> $dest"
    manifest::record "$key" "$(jq -n \
        --arg p "$dest" --arg u "$url" --arg v "${ver:-}" \
        --arg md5 "${LAST_FETCH_MD5:-}" --argjson bytes "${LAST_FETCH_BYTES:-0}" \
        '{uniprot:"'"$acc"'", type:"structure", source:"alphafold", source_url:$u,
          db_release:("AlphaFold v" + $v), format:"'"$fmt"'", status:"downloaded",
          files:[{path:$p, bytes:$bytes, md5:$md5}]}')"
    return 0
}

# downloaders_structure_download::download_pdb <pdbid> <outdir> <fmt>
downloaders_structure_download::download_pdb() {
    local id="${1^^}" outdir="$2" fmt="${3:-pdb}"
    local key="${id}:pdb:${fmt}"
    local url="${RCSB_FILES}/${id}.${fmt}"
    local dest="${outdir}/structures/pdb/${id}.${fmt}"

    if downloaders_common::already_have "$dest" "$(manifest::stored_md5 "$key")"; then
        log_info "[$id] PDB file already present - skipping"
        manifest::record_run_only "$key" "$(jq -n --arg p "$dest" '{pdb_id:"'"$id"'", type:"structure", source:"rcsb-pdb", status:"skipped", files:[{path:$p}]}')"
        return 0
    fi

    local rc
    downloaders_common::atomic_fetch "$url" "$dest"; rc=$?
    if [[ $rc -ne 0 ]]; then
        [[ "$rc" == "${EX_NETWORK:-5}" ]] && rc="${EX_NOTFOUND:-4}"   # RCSB 404s on a bad id
        log_error "[$id] PDB download failed"
        manifest::record "$key" "$(jq -n '{pdb_id:"'"$id"'", type:"structure", source:"rcsb-pdb", status:"failed"}')"
        return "$rc"
    fi

    log_success "[$id] PDB $fmt -> $dest"
    manifest::record "$key" "$(jq -n \
        --arg p "$dest" --arg u "$url" \
        --arg md5 "${LAST_FETCH_MD5:-}" --argjson bytes "${LAST_FETCH_BYTES:-0}" \
        '{pdb_id:"'"$id"'", type:"structure", source:"rcsb-pdb", source_url:$u,
          format:"'"$fmt"'", status:"downloaded",
          files:[{path:$p, bytes:$bytes, md5:$md5}]}')"
    return 0
}

# Collect ids from a comma list + an optional file (one per line, # comments ok)
downloaders_structure_download::_ids() {
    local csv="$1" file="$2"
    [[ -n "$csv" ]] && tr ',' '\n' <<< "$csv" | sed 's/[[:space:]]//g' | grep -v '^$'
    [[ -n "$file" && -f "$file" ]] && grep -vE '^\s*#|^\s*$' "$file"
}

# downloaders_structure_download::run <outdir> <fmt>
downloaders_structure_download::run() {
    local outdir="$1" fmt="${2:-pdb}"
    downloaders_common::check_command curl || return "${EX_DEPENDENCY:-3}"
    downloaders_common::check_command jq   || return "${EX_DEPENDENCY:-3}"

    local ok=0 fail=0 acc id rc last_rc=0

    while IFS= read -r acc; do
        [[ -z "$acc" ]] && continue
        downloaders_structure_download::download_alphafold "$acc" "$outdir" "$fmt"; rc=$?
        if [[ $rc -eq 0 ]]; then ((ok+=1)); else ((fail+=1)); last_rc=$rc; fi
    done < <(downloaders_structure_download::_ids "$STRUCTURE_ALPHAFOLD" "$STRUCTURE_ALPHAFOLD_FILE")

    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        downloaders_structure_download::download_pdb "$id" "$outdir" "$fmt"; rc=$?
        if [[ $rc -eq 0 ]]; then ((ok+=1)); else ((fail+=1)); last_rc=$rc; fi
    done < <(downloaders_structure_download::_ids "$STRUCTURE_PDB" "$STRUCTURE_PDB_FILE")

    log_info "═══════════════════════════════════════"
    log_info "Structure Download Summary: $ok ok | $fail failed"
    log_info "═══════════════════════════════════════"

    # A single requested id: surface its own error code (e.g. 4 not-found)
    # rather than the generic all-failed 5.
    (( ok + fail == 1 )) && return "$last_rc"
    downloaders_common::batch_exit_code "$ok" "$fail"
}
