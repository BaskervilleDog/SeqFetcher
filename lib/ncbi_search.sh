#!/usr/bin/env bash

search_metadata_by_organism() {
    local organism="$1"
    local output_file="${2:-taxonomy_metadata.tsv}"
    
    # Input validation
    [[ -z "$organism" ]] && {
        log_error "Organism name required"
        return 1
    }
    
    log_step "Fetching taxonomy metadata for: $organism"
    
    # Check dependencies
    require_datasets || return 1
    command -v jq >/dev/null 2>&1 || {
        log_error "jq is required but not installed"
        return 1
    }
    
    local tmp_json tmp_tsv
    tmp_json=$(mktemp) || return 1
    tmp_tsv=$(mktemp) || { rm -f "$tmp_json"; return 1; }
    
    # Fetch taxonomy data with error handling
    if ! datasets summary taxonomy taxon "$organism" > "$tmp_json" 2>&1; then
        log_error "Failed to fetch taxonomy data from NCBI"
        rm -f "$tmp_json" "$tmp_tsv"
        return 1
    fi
    
    [[ ! -s "$tmp_json" ]] && {
        log_error "No data returned from NCBI"
        rm -f "$tmp_json" "$tmp_tsv"
        return 1
    }
    
    # Check if reports exist
    local report_count
    report_count=$(jq -r '.reports | length' "$tmp_json" 2>/dev/null)
    
    [[ "$report_count" -eq 0 ]] && {
        log_error "No taxonomy data found for: $organism"
        rm -f "$tmp_json" "$tmp_tsv"
        return 1
    }
    
    # Extract taxonomy metadata to TSV
    jq -r '
        .reports[0] as $r |
        [ $r.taxonomy.classification.species.name // "NA",
          $r.taxonomy.curator_common_name // "NA",
          ($r.taxonomy.classification.species.id // 0 | tostring),
          $r.taxonomy.classification.domain.name // "NA",
          $r.taxonomy.classification.kingdom.name // "NA",
          $r.taxonomy.classification.phylum.name // "NA",
          $r.taxonomy.classification.class.name // "NA",
          $r.taxonomy.classification.order.name // "NA",
          $r.taxonomy.classification.family.name // "NA",
          $r.taxonomy.classification.genus.name // "NA",
          (($r.taxonomy.counts // []) | map(select(.type=="COUNT_TYPE_ASSEMBLY")) | .[0].count // 0 | tostring),
          (($r.taxonomy.counts // []) | map(select(.type=="COUNT_TYPE_GENE")) | .[0].count // 0 | tostring),
          (($r.taxonomy.counts // []) | map(select(.type=="COUNT_TYPE_PROTEIN_CODING")) | .[0].count // 0 | tostring),
          (($r.taxonomy.counts // []) | map(select(.type=="COUNT_TYPE_tRNA")) | .[0].count // 0 | tostring),
          (($r.taxonomy.counts // []) | map(select(.type=="COUNT_TYPE_rRNA")) | .[0].count // 0 | tostring),
          (($r.taxonomy.counts // []) | map(select(.type=="COUNT_TYPE_ncRNA")) | .[0].count // 0 | tostring),
          (($r.taxonomy.counts // []) | map(select(.type=="COUNT_TYPE_miscRNA")) | .[0].count // 0 | tostring)
        ] | @tsv
    ' "$tmp_json" > "$tmp_tsv"
    
    # Extract summary stats using proper tab delimiter
    local species_name common_name tax_id assembly_count
    IFS=$'\t' read -r species_name common_name tax_id _ _ _ _ _ _ _ assembly_count _ <<< "$(cat "$tmp_tsv")"
    
    log_info "Species: $species_name ($common_name)"
    log_info "Taxonomy ID: $tax_id"
    log_info "Assemblies in NCBI: $assembly_count"
    echo
    
    # Write TSV table to file
    if [[ -n "$output_file" ]]; then
        {
            printf "SPECIES\tCOMMON_NAME\tTAX_ID\tDOMAIN\tKINGDOM\tPHYLUM\tCLASS\tORDER\tFAMILY\tGENUS\tASSEMBLIES\tGENES\tPROTEIN_CODING\ttRNA\trRNA\tncRNA\tmiscRNA\n"
            cat "$tmp_tsv"
        } > "$output_file"
        log_info "Taxonomy table written to: $output_file"
    fi
    
    # Pretty table display
    echo "TAXONOMY CLASSIFICATION:"
    printf "%-20s %s\n" "Domain:" "$(cut -f4 "$tmp_tsv")"
    printf "%-20s %s\n" "Kingdom:" "$(cut -f5 "$tmp_tsv")"
    printf "%-20s %s\n" "Phylum:" "$(cut -f6 "$tmp_tsv")"
    printf "%-20s %s\n" "Class:" "$(cut -f7 "$tmp_tsv")"
    printf "%-20s %s\n" "Order:" "$(cut -f8 "$tmp_tsv")"
    printf "%-20s %s\n" "Family:" "$(cut -f9 "$tmp_tsv")"
    printf "%-20s %s\n" "Genus:" "$(cut -f10 "$tmp_tsv")"
    printf "%-20s %s\n" "Species:" "$(cut -f1 "$tmp_tsv")"
    echo
    
    echo "SEQUENCE COUNTS:"
    printf "%-20s %s\n" "Assemblies:" "$(cut -f11 "$tmp_tsv")"
    printf "%-20s %s\n" "Genes:" "$(cut -f12 "$tmp_tsv")"
    printf "%-20s %s\n" "Protein-coding:" "$(cut -f13 "$tmp_tsv")"
    printf "%-20s %s\n" "tRNA:" "$(cut -f14 "$tmp_tsv")"
    printf "%-20s %s\n" "rRNA:" "$(cut -f15 "$tmp_tsv")"
    printf "%-20s %s\n" "ncRNA:" "$(cut -f16 "$tmp_tsv")"
    printf "%-20s %s\n" "miscRNA:" "$(cut -f17 "$tmp_tsv")"
    echo
    
    # Cleanup
    rm -f "$tmp_json" "$tmp_tsv"
}

search_assemblies_by_organism() {
    local organism="$1"
    local output_file="${2:-assemblies.tsv}"
    
    # Input validation
    [[ -z "$organism" ]] && {
        log_error "Organism name required"
        return 1
    }
    
    log_step "Searching NCBI assemblies for: $organism"
    
    # Check dependencies
    require_datasets || return 1
    command -v jq >/dev/null 2>&1 || {
        log_error "jq is required but not installed"
        return 1
    }
    
    local tmp_json tmp_tsv
    tmp_json=$(mktemp) || return 1
    tmp_tsv=$(mktemp) || { rm -f "$tmp_json"; return 1; }
    
    # Fetch assemblies with error handling
    if ! datasets summary genome taxon "$organism" \
        --assembly-level complete,chromosome,scaffold,contig \
        --limit 999999 > "$tmp_json" 2>&1; then
        log_error "Failed to fetch data from NCBI"
        rm -f "$tmp_json" "$tmp_tsv"
        return 1
    fi
    
    [[ ! -s "$tmp_json" ]] && {
        log_error "No data returned from NCBI"
        rm -f "$tmp_json" "$tmp_tsv"
        return 1
    }
    
    # Combined stats extraction (single jq pass)
    local stats
    stats=$(jq -r '
        .reports | 
        {
            total: length,
            gcf: ([.[].accession | select(startswith("GCF_"))] | length),
            ref: ([.[].assembly_info.refseq_category | select(. == "reference genome")] | length),
            chr: ([.[].assembly_info.assembly_level | select(. == "Chromosome" or . == "Complete Genome")] | length)
        } | "\(.total)\t\(.gcf)\t\(.ref)\t\(.chr)"
    ' "$tmp_json")
    
    IFS=$'\t' read -r total_found gcf_count ref_count chr_count <<< "$stats"
    
    [[ "$total_found" -eq 0 ]] && {
        log_error "No assemblies found for: $organism"
        rm -f "$tmp_json" "$tmp_tsv"
        return 1
    }
    
    # Ranking + extraction to TSV
    jq -r '
        .reports[]
        | {
            acc: .accession,
            org: .organism.organism_name,
            level: .assembly_info.assembly_level,
            status: .assembly_info.assembly_status,
            refcat: (.assembly_info.refseq_category // "none"),
            name: .assembly_info.assembly_name
          }
        | .priority = (
            (if .acc | startswith("GCF_") then 0 else 5 end) * 100
            + (if .refcat == "reference genome" then 0 elif .refcat == "representative genome" then 1 else 3 end) * 10
            + (if .level == "Chromosome" or .level == "Complete Genome" then 0 elif .level == "Scaffold" then 1 else 2 end)
          )
        | [
            .priority,
            .acc,
            .org,
            (.level // "NA"),
            (.status // "NA"),
            .refcat,
            (.name // "NA")
          ]
        | @tsv
    ' "$tmp_json" \
    | sort -n \
    | cut -f2- \
    | head -n 50\
    > "$tmp_tsv"
    
    local shown
    shown=$(wc -l < "$tmp_tsv")
    
    log_info "Found $total_found assemblies in NCBI"
    log_info "Showing top $shown assemblies (ranked: GCF + reference first)"
    log_info "Stats: RefSeq(GCF)=$gcf_count, Reference genomes=$ref_count, Chromosome-level=$chr_count"
    echo
    
    # Write TSV table to file
    if [[ -n "$output_file" ]]; then
    {
        printf "ACCESSION\tORGANISM\tLEVEL\tSTATUS\tREFSEQ_CATEGORY\tNAME\n"
        cat "$tmp_tsv"
    } > "$output_file"
    log_info "Table written to $output_file"
    
            # Create accession-only file
        local accession_file="${output_file%.tsv}_accessions.txt"
        cut -f1 "$tmp_tsv" > "$accession_file"
        log_info "Accession list written to: $accession_file"

    fi
    
    # Pretty table display
    printf "%-4s %-18s %-30s %-12s %-10s %-18s %s\n" \
        "ID" "ACCESSION" "ORGANISM" "LEVEL" "STATUS" "REFSEQ_CATEGORY" "NAME"
    printf "%-4s %-18s %-30s %-12s %-10s %-18s %s\n" \
        "----" "------------------" "------------------------------" "------------" "----------" "------------------" "----------------------------"
    
    nl -w2 -s"$(printf '\t')" "$tmp_tsv" | awk -F'\t' '{
        printf "%-4s %-18s %-30.30s %-12s %-10s %-18s %s\n",
        $1, $2, substr($3,1,30), $4, $5, $6, $7
    }'
    echo
    
    # Cleanup
    rm -f "$tmp_json" "$tmp_tsv"
}

extract_gene_ids_from_reference() {
    local organism="$1"
    local output_file="${2:-gene_ids.txt}"
    local metadata_file="${output_file%.txt}_metadata.tsv"

    [[ -z "$organism" ]] && { log_error "Organism name required"; return 1; }

    log_step "Extracting gene IDs from reference genome for: $organism"

    require_datasets || return 1
    command -v jq >/dev/null 2>&1 || { log_error "jq is required"; return 1; }
    command -v parallel >/dev/null 2>&1 || { log_error "GNU parallel is required"; return 1; }

    local tmp_json tmp_dir
    tmp_json=$(mktemp) || return 1
    tmp_dir=$(mktemp -d) || { rm -f "$tmp_json"; return 1; }

    log_info "Searching for reference genome..."
    if ! datasets summary genome taxon "$organism" \
        --assembly-level complete,chromosome \
        --limit 999999 > "$tmp_json" 2>&1; then
        log_error "Failed to fetch genome data"
        rm -f "$tmp_json" && rm -rf "$tmp_dir"
        return 1
    fi

    [[ ! -s "$tmp_json" ]] && { log_error "No genome data returned"; rm -f "$tmp_json"; rm -rf "$tmp_dir"; return 1; }

    local accession
    accession=$(jq -r '
        .reports[]
        | select(.assembly_info.refseq_category=="reference genome")
        | .accession
        | select(startswith("GCF_"))
    ' "$tmp_json" | head -n1)

    [[ -z "$accession" ]] && {
        accession=$(jq -r '
            .reports[]
            | select(.assembly_info.refseq_category=="reference genome")
            | .accession
        ' "$tmp_json" | head -n1)
    }

    [[ -z "$accession" ]] && { log_error "No reference genome found"; rm -f "$tmp_json"; rm -rf "$tmp_dir"; return 1; }

    log_info "Found reference genome: $accession"

    log_step "Downloading genome annotation..."
    if ! datasets download genome accession "$accession" \
        --include gtf,gff3 \
        --filename "$tmp_dir/genome.zip" >/dev/null 2>&1; then
        log_error "Failed to download genome annotation"
        rm -f "$tmp_json"; rm -rf "$tmp_dir"; return 1
    fi

    log_info "Extracting annotation files..."
    unzip -q "$tmp_dir/genome.zip" -d "$tmp_dir" || { log_error "Failed to extract files"; rm -f "$tmp_json"; rm -rf "$tmp_dir"; return 1; }

    local annotation_file
    annotation_file=$(find "$tmp_dir" -name "*.gtf" -o -name "*.gff" -o -name "*.gff3" | head -n1)
    [[ -z "$annotation_file" || ! -f "$annotation_file" ]] && { log_error "No GTF/GFF found"; rm -f "$tmp_json"; rm -rf "$tmp_dir"; return 1; }
    log_info "Found annotation file: $(basename "$annotation_file")"

    echo -e "EntrezID\tSymbol\tGeneID\tChromosome\tStart\tEnd\tStrand\tGeneType" > "$metadata_file"

    mkdir -p "$tmp_dir/chunks"
    grep -v "^#" "$annotation_file" | awk -F'\t' '$3=="gene"' > "$tmp_dir/genes.gff"
    split -l $(( ($(wc -l < "$tmp_dir/genes.gff") / 4) + 1 )) "$tmp_dir/genes.gff" "$tmp_dir/chunks/chunk_"

    log_step "Extracting gene metadata (parallel)..."

    # Correct parallel + awk syntax
    find "$tmp_dir/chunks" -type f | parallel -j4 '
        awk -F"\t" '\''{
            chr=$1; start=$4; end=$5; strand=$7; attrs=$9;
            match(attrs,/Dbxref=.*?GeneID:([0-9]+)/,e);
            match(attrs,/Name=([^;]+)/,b);
            match(attrs,/ID=([^;]+)/,g);
            match(attrs,/biotype=([^;]+)/,t);
            print (e[1]?e[1]:"") "\t" (b[1]?b[1]:"") "\t" (g[1]?g[1]:"") "\t" chr "\t" start "\t" end "\t" strand "\t" (t[1]?t[1]:"")
        }'\'' {} > {}.out
    '

    cat "$tmp_dir"/chunks/*.out >> "$metadata_file"

    # Extract numeric Entrez IDs only
    awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}' "$metadata_file" | sort -u > "$output_file"

    local gene_count
    gene_count=$(wc -l < "$output_file")

    [[ $gene_count -eq 0 ]] && { log_error "No Entrez IDs extracted"; rm -f "$tmp_json"; rm -rf "$tmp_dir"; return 1; }

    log_info "═══════════════════════════════════════"
    log_info "Gene ID Extraction Complete"
    log_info "Reference genome: $accession"
    log_info "Total genes found: $gene_count"
    log_info "Entrez IDs saved to: $output_file"
    log_info "Full metadata saved to: $metadata_file"
    log_info "═══════════════════════════════════════"

    log_info "Preview (first 10 Entrez IDs):"
    head -n10 "$output_file" | nl -w2 -s". "
    [[ $gene_count -gt 10 ]] && echo "... and $((gene_count - 10)) more"
    echo

    rm -f "$tmp_json"
    rm -rf "$tmp_dir"

    return 0
}