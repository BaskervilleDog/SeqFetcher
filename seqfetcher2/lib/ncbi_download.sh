#!/usr/bin/env bash

#==============================================================
# Download single assembly (basic)
#==============================================================

download_assembly() {
    local accession="$1"
    local outdir="${2:-downloads}"
    
    [[ -z "$accession" ]] && { echo "ERROR: Empty accession" >&2; return 1; }
    
    accession=$(echo "$accession" | xargs)
    [[ -z "$accession" ]] && { echo "ERROR: Accession is empty after trimming" >&2; return 1; }
    
    
    if ! command -v datasets >/dev/null 2>&1; then
        echo "ERROR: datasets command not found. Please install NCBI datasets CLI." >&2
        return 1
    fi
    
    mkdir -p "$outdir/$accession"
    local zip="$outdir/$accession/${accession}.zip"
    
    
    echo "[START] Downloading: $accession" >&2
    echo "DEBUG: Running command: datasets download genome accession $accession --include genome,gff3,gtf,cds,protein --filename $zip" >&2
    
    if datasets download genome accession "$accession" \
        --include genome,gff3,gtf,cds,protein \
        --filename "$zip"; then
        
        echo "DEBUG: Download completed, extracting..." >&2
        if unzip -q "$zip" -d "$outdir/$accession" 2>/dev/null; then
            rm -f "$zip"
            echo "[SUCCESS] Downloaded: $accession" >&2
            echo "DEBUG: Files extracted to: $outdir/$accession" >&2
            return 0
        else
            echo "ERROR: Failed to extract: $accession" >&2
            rm -f "$zip"
            return 1
        fi
    else
        echo "ERROR: Download failed: $accession" >&2
        return 1
    fi
}

#==============================================================
# Download multiple assemblies in parallel
#==============================================================

download_assemblies_parallel() {
    local accession_file="$1"
    local outdir="$2"
    local jobs="${3:-4}"
    
    [[ ! -f "$accession_file" ]] && { log_error "Accession file not found: $accession_file"; return 1; }
    
    mapfile -t accessions < <(grep -vE '^\s*#|^\s*$' "$accession_file")
    local total=${#accessions[@]}
    
    [[ $total -eq 0 ]] && { log_error "No valid accessions found"; return 1; }
    
    log_info "Found $total accessions to download"
    log_info "Starting parallel downloads..."
    echo
    
    local count=0
    local pids=()
    local successful=0
    local failed=0
    
    for acc in "${accessions[@]}"; do
        count=$((count + 1))
        
        echo "[$count/$total] Downloading: $acc"
        
        download_assembly "$acc" "$outdir" "true" &
        pids+=($!)
        
        # Limit parallel jobs
        while [[ ${#pids[@]} -ge $jobs ]]; do
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                else
                    wait "$pid"
                    [[ $? -eq 0 ]] && ((successful++)) || ((failed++))
                fi
            done
            pids=("${new_pids[@]}")
            [[ ${#pids[@]} -ge $jobs ]] && sleep 0.5
        done
    done
    
    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
        [[ $? -eq 0 ]] && ((successful++)) || ((failed++))
    done
    
    echo
    log_info "═══════════════════════════════════════"
    log_info "Download Summary"
    log_info "═══════════════════════════════════════"
    log_info "Total: $total"
    echo "[SUCCESS] Successful: $successful"
    [[ $failed -gt 0 ]] && log_error "Failed: $failed"
    log_info "═══════════════════════════════════════"
    echo
}

#==============================================================
# Download genes in batches
#==============================================================

download_genes_batches() {
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
    echo
    
    local seq_types="gene,rna,protein,cds,product-report"
    
    download_batch() {
        local batch_num="$1"
        local batch_start="$2"
        local batch_end="$3"
        shift 3
        local batch_ids=("$@")
        
        local batch_name="batch_${batch_num}_genes_${batch_start}_to_${batch_end}"
        local zip_file="$outdir/${batch_name}.zip"
        local extract_dir="$outdir/$batch_name"
        
        echo "[$batch_num/$total_batches] Downloading ${#batch_ids[@]} genes..."
        
        if datasets download gene gene-id "${batch_ids[@]}" \
            --include "$seq_types" \
            --filename "$zip_file" >/dev/null 2>&1; then
            
            echo "[$batch_num/$total_batches] Extracting..."
            mkdir -p "$extract_dir"
            
            if unzip -q "$zip_file" -d "$extract_dir" 2>/dev/null; then
                rm -f "$zip_file"
                local size=$(du -sh "$extract_dir" 2>/dev/null | cut -f1 || echo "unknown")
                echo "[$batch_num/$total_batches] ✓ Complete: $batch_name ($size)"
                return 0
            else
                echo "[$batch_num/$total_batches] ✗ Extraction failed: $batch_name"
                rm -f "$zip_file"
                return 1
            fi
        else
            echo "[$batch_num/$total_batches] ✗ Download failed: $batch_name"
            rm -f "$zip_file"
            return 1
        fi
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
                    wait "$pid"
                    [[ $? -eq 0 ]] && ((successful++)) || ((failed++))
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
        wait "$pid"
        [[ $? -eq 0 ]] && ((successful++)) || ((failed++))
    done
    
    echo
    log_info "═══════════════════════════════════════"
    log_info "Gene Download Summary"
    log_info "═══════════════════════════════════════"
    log_info "Total batches: $total_batches"
    echo "[SUCCESS] Successful: $successful"
    [[ $failed -gt 0 ]] && log_error "Failed: $failed"
    log_info "═══════════════════════════════════════"
    echo
}

#==============================================================
# Interactive assembly selection
#==============================================================

download_assemblies_interactive() {
    local tsv_file="$1"
    local outdir="$2"
    
    [[ ! -f "$tsv_file" ]] && {
        log_error "TSV file not found: $tsv_file"
        return 1
    }
    
    echo
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
    
    echo
    log_info "Downloading $acc_count assemblies..."
    echo
    
    download_assemblies_parallel "$tmp_acc_file" "$outdir" 4
    
    rm -f "$tmp_acc_file"
}

# Export functions for subshells
export -f download_assembly
export -f download_assemblies_parallel
export -f download_genes_batches
export -f download_assemblies_interactive