#!/usr/bin/env bash

#==============================================================
# Download single assembly (basic)
#==============================================================

downloaders_ncbi_download::download_assembly() {
    local accession="$1"
    local outdir="${2:-downloads}"

    [[ -z "$accession" ]] && { log_error "Empty accession"; return "${EX_USAGE:-2}"; }
    accession=$(echo "$accession" | xargs)
    [[ -z "$accession" ]] && { log_error "Accession is empty after trimming"; return "${EX_USAGE:-2}"; }

    command -v datasets >/dev/null 2>&1 || {
        die "datasets command not found - install the NCBI datasets CLI" "${EX_DEPENDENCY:-3}"
    }

    local dest_dir="$outdir/$accession"
    local key="${accession}:assembly"
    local incl="genome,gff3,gtf,cds,protein"

    # Skip-by-default: a completed lockfile entry + an on-disk directory is
    # enough (assemblies are multi-file, so we don't checksum-verify here).
    if [[ "${FORCE:-false}" != true ]] && manifest::is_done "$key" && [[ -d "$dest_dir" ]]; then
        log_info "[$accession] already downloaded - skipping (use --force to refetch)"
        manifest::record_run_only "$key" "$(jq -n --arg a "$accession" --arg d "$dest_dir" \
            '{accession:$a, type:"assembly", source:"ncbi-datasets", status:"skipped", files:[{path:$d}]}')"
        return 0
    fi

    log_info "[$accession] downloading assembly ($incl)"

    local stage; stage="$(downloaders_common::new_stage)" || return "${EX_ERROR:-1}"
    local zip="$stage/${accession}.zip"

    if ! datasets download genome accession "$accession" \
            --include "$incl" --filename "$zip"; then
        log_error "[$accession] download failed"
        rm -rf "$stage"
        manifest::record "$key" "$(jq -n --arg a "$accession" '{accession:$a, type:"assembly", source:"ncbi-datasets", status:"failed"}')"
        return "${EX_NETWORK:-5}"
    fi

    if ! unzip -q "$zip" -d "$stage/extracted" 2>/dev/null; then
        log_error "[$accession] failed to extract archive"
        rm -rf "$stage"
        manifest::record "$key" "$(jq -n --arg a "$accession" '{accession:$a, type:"assembly", source:"ncbi-datasets", status:"failed"}')"
        return "${EX_ERROR:-1}"
    fi
    rm -f "$zip"

    if ! downloaders_common::promote "$stage/extracted" "$dest_dir"; then
        log_error "[$accession] failed to move files into place"
        rm -rf "$stage"
        return "${EX_ERROR:-1}"
    fi
    rm -rf "$stage"

    log_success "[$accession] downloaded to $dest_dir"
    downloaders_ncbi_download::_record_dir "$key" "$accession" "assembly" "ncbi-datasets" "$dest_dir"
    return 0
}

# Records a downloaded directory tree into the lockfile: every regular file
# as {path, bytes}, plus a total. Cheap enough; skips per-file md5 (large
# multi-file payloads).
downloaders_ncbi_download::_record_dir() {
    local key="$1" accession="$2" type="$3" source="$4" dir="$5"
    command -v jq >/dev/null 2>&1 || return 0
    local ds_ver=""
    command -v datasets >/dev/null 2>&1 && ds_ver="$(datasets --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)"
    local files_json p
    files_json="$(
        while IFS= read -r p; do
            printf '%s\t%s\n' "$(downloaders_common::_bytes "$p")" "$p"
        done < <(find "$dir" -type f) \
        | jq -R -s 'split("\n") | map(select(length>0)) | map(split("\t"))
                    | map({path: .[1], bytes: (.[0]|tonumber? // 0)})'
    )"
    [[ -z "$files_json" ]] && files_json='[]'
    manifest::record "$key" "$(jq -n \
        --arg a "$accession" --arg t "$type" --arg s "$source" --arg dv "$ds_ver" \
        --argjson f "$files_json" \
        '{accession:$a, type:$t, source:$s, status:"downloaded",
          files:$f, bytes:($f | map(.bytes) | add // 0)}
         + (if $dv != "" then {tool:{datasets:$dv}} else {} end)')"
}

#==============================================================
# Download multiple assemblies in parallel
#==============================================================

downloaders_ncbi_download::download_assemblies_parallel() {
    local accession_file="$1"
    local outdir="$2"
    local jobs="${3:-4}"
    
    [[ ! -f "$accession_file" ]] && { log_error "Accession file not found: $accession_file"; return "${EX_USAGE:-2}"; }

    mapfile -t accessions < <(grep -vE '^\s*#|^\s*$' "$accession_file")
    local total=${#accessions[@]}

    [[ $total -eq 0 ]] && { log_error "No valid accessions found"; return "${EX_USAGE:-2}"; }

    log_info "Found $total accessions to download"
    log_info "Starting parallel downloads..."

    local count=0
    local pids=()
    local successful=0
    local failed=0

    for acc in "${accessions[@]}"; do
        count=$((count + 1))

        log_info "[$count/$total] Downloading: $acc"

        downloaders_ncbi_download::download_assembly "$acc" "$outdir" "true" &
        pids+=($!)
        
        # Limit parallel jobs
        while [[ ${#pids[@]} -ge $jobs ]]; do
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                else
                    if wait "$pid"; then ((successful+=1)); else ((failed+=1)); fi
                fi
            done
            pids=("${new_pids[@]}")
            [[ ${#pids[@]} -ge $jobs ]] && sleep 0.5
        done
    done
    
    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        if wait "$pid"; then ((successful+=1)); else ((failed+=1)); fi
    done
    
    log_info "═══════════════════════════════════════"
    log_info "Download Summary"
    log_info "Total: $total | Successful: $successful | Failed: $failed"
    log_info "═══════════════════════════════════════"

    downloaders_common::batch_exit_code "$successful" "$failed"
}

#==============================================================
# Download genes in batches
#==============================================================

downloaders_ncbi_download::download_genes_batches() {
    local gene_file="$1"
    local outdir="$2"
    local jobs="${3:-4}"
    local batch_size="${4:-500}"
    
    [[ ! -f "$gene_file" ]] && { log_error "Gene file not found: $gene_file"; return 1; }
    
    mapfile -t gene_ids < <(grep -vE '^\s*#|^\s*$' "$gene_file" | sort -u)
    [[ ${#gene_ids[@]} -eq 0 ]] && { log_error "No valid gene IDs found"; return 1; }
    
    mkdir -p "$outdir"
    
    local total_genes=${#gene_ids[@]}
    local total_batches=$(( (total_genes + batch_size - 1) / batch_size ))
    
    log_info "Processing $total_genes gene IDs"
    log_info "Batch size: $batch_size genes per download"
    log_info "Total batches: $total_batches"
    echo >&2
    
    local seq_types="gene,rna,protein,cds,product-report"
    
    download_batch() {
        local batch_num="$1"
        local batch_start="$2"
        local batch_end="$3"
        shift 3
        local batch_ids=("$@")

        local batch_name="batch_${batch_num}_genes_${batch_start}_to_${batch_end}"
        local extract_dir="$outdir/$batch_name"
        local key="genes:${batch_start}-${batch_end}"

        if [[ "${FORCE:-false}" != true ]] && manifest::is_done "$key" && [[ -d "$extract_dir" ]]; then
            log_info "[$batch_num/$total_batches] $batch_name already present - skipping"
            manifest::record_run_only "$key" "$(jq -n --arg d "$extract_dir" \
                '{type:"gene-batch", source:"ncbi-datasets", status:"skipped", files:[{path:$d}]}')"
            return 0
        fi

        log_info "[$batch_num/$total_batches] Downloading ${#batch_ids[@]} genes..."

        local stage; stage="$(downloaders_common::new_stage)" || return 1
        local zip_file="$stage/${batch_name}.zip"

        if ! datasets download gene gene-id "${batch_ids[@]}" \
                --include "$seq_types" --filename "$zip_file" >/dev/null 2>&1; then
            log_error "[$batch_num/$total_batches] download failed: $batch_name"
            rm -rf "$stage"
            manifest::record "$key" "$(jq -n '{type:"gene-batch", source:"ncbi-datasets", status:"failed"}')"
            return 1
        fi

        if ! unzip -q "$zip_file" -d "$stage/extracted" 2>/dev/null \
           || ! downloaders_common::promote "$stage/extracted" "$extract_dir"; then
            log_error "[$batch_num/$total_batches] extraction failed: $batch_name"
            rm -rf "$stage"
            manifest::record "$key" "$(jq -n '{type:"gene-batch", source:"ncbi-datasets", status:"failed"}')"
            return 1
        fi
        rm -rf "$stage"

        local size; size=$(du -sh "$extract_dir" 2>/dev/null | cut -f1 || echo "unknown")
        log_success "[$batch_num/$total_batches] complete: $batch_name ($size)"
        downloaders_ncbi_download::_record_dir "$key" "$batch_name" "gene-batch" "ncbi-datasets" "$extract_dir"
        return 0
    }

    export -f download_batch
    export seq_types outdir total_batches
    
    local i=0
    local batch_num=1
    local pids=()
    local successful=0
    local failed=0
    
    while [[ $i -lt $total_genes ]]; do
        local batch_end=$((i + batch_size - 1))
        [[ $batch_end -ge $total_genes ]] && batch_end=$((total_genes - 1))
        
        local batch_ids=("${gene_ids[@]:i:batch_size}")
        local actual_count=${#batch_ids[@]}
        
        download_batch "$batch_num" "$((i + 1))" "$((i + actual_count))" "${batch_ids[@]}" &
        pids+=($!)
        
        # Limit parallel jobs
        while [[ ${#pids[@]} -ge $jobs ]]; do
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                else
                    if wait "$pid"; then ((successful+=1)); else ((failed+=1)); fi
                fi
            done
            pids=("${new_pids[@]}")
            [[ ${#pids[@]} -ge $jobs ]] && sleep 0.5
        done
        
        i=$((i + batch_size))
        batch_num=$((batch_num + 1))
    done
    
    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        if wait "$pid"; then ((successful+=1)); else ((failed+=1)); fi
    done
    
    log_info "═══════════════════════════════════════"
    log_info "Gene Download Summary"
    log_info "Total batches: $total_batches | Successful: $successful | Failed: $failed"
    log_info "═══════════════════════════════════════"

    downloaders_common::batch_exit_code "$successful" "$failed"
}

#==============================================================
# Interactive assembly selection
#==============================================================

downloaders_ncbi_download::download_assemblies_interactive() {
    local tsv_file="$1"
    local outdir="$2"
    
    [[ ! -f "$tsv_file" ]] && {
        log_error "TSV file not found: $tsv_file"
        return 1
    }
    
    echo >&2
    log_info "Enter assembly IDs to download (comma or space separated, or ranges like 1-5)"
    log_info "Example: 1,3,5 or 1 3 5 or 1-5"
    read -rp "IDs: " selection
    
    [[ -z "$selection" ]] && {
        log_info "No selection made"
        return 0
    }
    
    # Parse selection (handle comma, space, and ranges)
    local ids=()
    selection="${selection//,/ }"
    
    for item in $selection; do
        if [[ "$item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            # Handle range (e.g., 1-5)
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            for ((i=start; i<=end; i++)); do
                ids+=("$i")
            done
        elif [[ "$item" =~ ^[0-9]+$ ]]; then
            ids+=("$item")
        else
            log_error "Invalid ID: $item (skipping)"
        fi
    done
    
    [[ ${#ids[@]} -eq 0 ]] && {
        log_error "No valid IDs provided"
        return 1
    }
    
    # Create temporary accession file
    local tmp_acc_file=$(mktemp)
    
    for id in "${ids[@]}"; do
        local accession
        accession=$(sed -n "$((id + 1))p" "$tsv_file" | cut -f1)
        
        if [[ -z "$accession" ]]; then
            log_error "ID $id not found in results"
            continue
        fi
        
        echo "$accession" >> "$tmp_acc_file"
    done
    
    local acc_count=$(wc -l < "$tmp_acc_file")
    
    if [[ $acc_count -eq 0 ]]; then
        log_error "No valid accessions to download"
        rm -f "$tmp_acc_file"
        return 1
    fi
    
    echo >&2
    log_info "Downloading $acc_count assemblies..."
    echo >&2
    
    downloaders_ncbi_download::download_assemblies_parallel "$tmp_acc_file" "$outdir" 4
    
    rm -f "$tmp_acc_file"
}

# Export functions for subshells
export -f downloaders_ncbi_download::download_assembly
export -f downloaders_ncbi_download::download_assemblies_parallel
export -f downloaders_ncbi_download::download_genes_batches
export -f downloaders_ncbi_download::download_assemblies_interactive