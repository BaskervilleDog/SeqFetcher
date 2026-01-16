#!/bin/bash

# ==============================================================================
# COMPREHENSIVE RNA-SEQ DATA DOWNLOAD TOOLKIT
# ==============================================================================
# This script provides multiple methods to download sequencing data from:
# - SRA (Sequence Read Archive)
# - GEO (Gene Expression Omnibus) 
# - NCBI Datasets
# - ENA (European Nucleotide Archive)
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default parameters
THREADS=${THREADS:-8}
MAX_SIZE="50G"
OUTPUT_DIR="downloads"
TEMP_DIR="temp_downloads"

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 not found. Please install it first."
        return 1
    fi
    return 0
}

create_dirs() {
    mkdir -p "${OUTPUT_DIR}/fastq"
    mkdir -p "${OUTPUT_DIR}/metadata"
    mkdir -p "${TEMP_DIR}"
    log_info "Created output directories"
}

# ==============================================================================
# METHOD 1: SRA-TOOLS (fasterq-dump)
# ==============================================================================

download_sra_fasterq() {
    log_step "METHOD 1: Using fasterq-dump (SRA Toolkit)"
    
    if ! check_command fasterq-dump; then
        log_error "Install with: conda install -c bioconda sra-tools"
        return 1
    fi
    
    local accession_list=$1
    
    if [[ ! -f "$accession_list" ]]; then
        log_error "Accession list file not found: $accession_list"
        return 1
    fi
    
    log_info "Reading accessions from: $accession_list"
    
    while IFS= read -r accession; do
        # Skip empty lines and comments
        [[ -z "$accession" || "$accession" =~ ^# ]] && continue
        
        log_info "Downloading $accession with fasterq-dump..."
        
        fasterq-dump "$accession" \
            --outdir "${OUTPUT_DIR}/fastq" \
            --temp "${TEMP_DIR}" \
            --threads "$THREADS" \
            --split-files \
            --progress \
            --verbose
        
        # Compress fastq files
        log_info "Compressing FASTQ files for $accession..."
        gzip "${OUTPUT_DIR}/fastq/${accession}"*.fastq 2>/dev/null || true
        
        log_info "✓ Completed: $accession"
        
    done < "$accession_list"
    
    # Cleanup temp directory
    rm -rf "${TEMP_DIR}"/*
    
    log_info "All downloads complete!"
}

# ==============================================================================
# METHOD 2: SRA-TOOLS with PREFETCH (for unreliable connections)
# ==============================================================================

download_sra_prefetch() {
    log_step "METHOD 2: Using prefetch + fasterq-dump (More robust)"
    
    if ! check_command prefetch || ! check_command fasterq-dump; then
        log_error "Install with: conda install -c bioconda sra-tools"
        return 1
    fi
    
    local accession_list=$1
    
    if [[ ! -f "$accession_list" ]]; then
        log_error "Accession list file not found: $accession_list"
        return 1
    fi
    
    while IFS= read -r accession; do
        [[ -z "$accession" || "$accession" =~ ^# ]] && continue
        
        log_info "Pre-fetching $accession..."
        
        # Download SRA file first
        prefetch "$accession" \
            --max-size "$MAX_SIZE" \
            --output-directory "${TEMP_DIR}" \
            --progress
        
        log_info "Converting $accession to FASTQ..."
        
        # Convert to FASTQ
        fasterq-dump "${TEMP_DIR}/${accession}/${accession}.sra" \
            --outdir "${OUTPUT_DIR}/fastq" \
            --temp "${TEMP_DIR}/temp" \
            --threads "$THREADS" \
            --split-files \
            --progress
        
        # Compress
        gzip "${OUTPUT_DIR}/fastq/${accession}"*.fastq 2>/dev/null || true
        
        # Clean up SRA file to save space
        rm -rf "${TEMP_DIR}/${accession}"
        
        log_info "✓ Completed: $accession"
        
    done < "$accession_list"
    
    log_info "All downloads complete!"
}

# ==============================================================================
# METHOD 3: PARALLEL-FASTQ-DUMP (fastest for multiple files)
# ==============================================================================

download_parallel_fastq() {
    log_step "METHOD 3: Using parallel-fastq-dump (Fastest)"
    
    if ! check_command parallel-fastq-dump; then
        log_error "Install with: pip install parallel-fastq-dump"
        return 1
    fi
    
    local accession_list=$1
    
    if [[ ! -f "$accession_list" ]]; then
        log_error "Accession list file not found: $accession_list"
        return 1
    fi
    
    while IFS= read -r accession; do
        [[ -z "$accession" || "$accession" =~ ^# ]] && continue
        
        log_info "Downloading $accession with parallel-fastq-dump..."
        
        parallel-fastq-dump \
            --sra-id "$accession" \
            --threads "$THREADS" \
            --outdir "${OUTPUT_DIR}/fastq" \
            --split-files \
            --tmpdir "${TEMP_DIR}" \
            --gzip
        
        log_info "✓ Completed: $accession"
        
    done < "$accession_list"
    
    log_info "All downloads complete!"
}

# ==============================================================================
# METHOD 4: ENA (European Nucleotide Archive) - Often faster than SRA
# ==============================================================================

download_ena() {
    log_step "METHOD 4: Using ENA (European Nucleotide Archive)"
    
    if ! check_command wget && ! check_command curl; then
        log_error "Please install wget or curl"
        return 1
    fi
    
    local accession_list=$1
    
    if [[ ! -f "$accession_list" ]]; then
        log_error "Accession list file not found: $accession_list"
        return 1
    fi
    
    local success_count=0
    local fail_count=0
    local failed_accessions=()
    
    while IFS= read -r accession; do
        [[ -z "$accession" || "$accession" =~ ^# ]] && continue
        
        log_info "Fetching ENA metadata for $accession..."
        
        # Get FTP links from ENA
        local ena_url="https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${accession}&result=read_run&fields=run_accession,fastq_ftp,fastq_md5,fastq_bytes"
        
        # Download metadata
        if command -v wget &> /dev/null; then
            wget -q -O "${TEMP_DIR}/${accession}_ena.txt" "$ena_url"
        else
            curl -s -o "${TEMP_DIR}/${accession}_ena.txt" "$ena_url"
        fi
        
        # Check if metadata was retrieved
        if [[ ! -s "${TEMP_DIR}/${accession}_ena.txt" ]]; then
            log_error "Failed to fetch metadata for $accession"
            ((fail_count++))
            failed_accessions+=("$accession")
            continue
        fi
        
        # Check if there are any FTP URLs (more than just header)
        local line_count=$(wc -l < "${TEMP_DIR}/${accession}_ena.txt")
        if [[ $line_count -lt 2 ]]; then
            log_error "No data returned for $accession from ENA"
            ((fail_count++))
            failed_accessions+=("$accession")
            continue
        fi
        
        # Parse FTP URLs (skip header)
        local has_files=false
        tail -n +2 "${TEMP_DIR}/${accession}_ena.txt" | while IFS=$'\t' read -r run_acc ftp_urls md5_sums file_sizes; do
            
            # Check if FTP URLs are empty
            if [[ -z "$ftp_urls" || "$ftp_urls" == "null" ]]; then
                log_error "No FASTQ files available at ENA for $run_acc"
                log_info "This accession may only be available through SRA directly"
                echo "FAILED" > "${TEMP_DIR}/${accession}_status.txt"
                continue
            fi
            
            has_files=true
            log_info "Downloading FASTQ files for $run_acc..."
            
            # Split multiple FTP URLs (semicolon-separated)
            IFS=';' read -ra FTP_ARRAY <<< "$ftp_urls"
            IFS=';' read -ra MD5_ARRAY <<< "$md5_sums"
            IFS=';' read -ra SIZE_ARRAY <<< "$file_sizes"
            
            for i in "${!FTP_ARRAY[@]}"; do
                ftp_url="${FTP_ARRAY[$i]}"
                expected_md5="${MD5_ARRAY[$i]}"
                expected_size="${SIZE_ARRAY[$i]}"
                
                # Add ftp:// prefix if missing
                [[ ! "$ftp_url" =~ ^ftp:// ]] && ftp_url="ftp://$ftp_url"
                
                filename=$(basename "$ftp_url")
                output_file="${OUTPUT_DIR}/fastq/${filename}"
                
                log_info "  Downloading: $filename (Size: $(numfmt --to=iec-i --suffix=B $expected_size 2>/dev/null || echo ${expected_size}B))"
                
                # Download with wget (supports resume)
                if wget -c -q --show-progress -O "$output_file" "$ftp_url"; then
                    log_info "  ✓ Downloaded: $filename"
                    
                    # Verify MD5 checksum
                    if [[ -n "$expected_md5" && "$expected_md5" != "null" ]]; then
                        log_info "  Verifying MD5 checksum..."
                        actual_md5=$(md5sum "$output_file" | awk '{print $1}')
                        
                        if [[ "$actual_md5" == "$expected_md5" ]]; then
                            log_info "  ✓ Checksum verified"
                        else
                            log_error "  ✗ Checksum mismatch for $filename"
                            log_error "    Expected: $expected_md5"
                            log_error "    Got: $actual_md5"
                        fi
                    fi
                    
                    # Verify file size
                    if [[ -n "$expected_size" && "$expected_size" != "null" ]]; then
                        actual_size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
                        if [[ "$actual_size" == "$expected_size" ]]; then
                            log_info "  ✓ File size verified"
                        else
                            log_error "  ✗ File size mismatch"
                        fi
                    fi
                else
                    log_error "  ✗ Failed to download $filename"
                    echo "FAILED" > "${TEMP_DIR}/${accession}_status.txt"
                fi
            done
        done
        
        # Check if any files were processed
        if [[ -f "${TEMP_DIR}/${accession}_status.txt" ]]; then
            ((fail_count++))
            failed_accessions+=("$accession")
            rm -f "${TEMP_DIR}/${accession}_status.txt"
        else
            if [[ "$has_files" == true ]]; then
                ((success_count++))
                log_info "✓ Completed: $accession"
            else
                ((fail_count++))
                failed_accessions+=("$accession")
                log_error "✗ No files downloaded for: $accession"
            fi
        fi
        
    done < "$accession_list"
    
    # Summary
    log_info ""
    log_info "==================== DOWNLOAD SUMMARY ===================="
    log_info "Successful: $success_count"
    log_info "Failed: $fail_count"
    
    if [[ $fail_count -gt 0 ]]; then
        log_info ""
        log_info "Failed accessions (try alternative methods):"
        for acc in "${failed_accessions[@]}"; do
            echo "  - $acc"
        done
        log_info ""
        log_info "Alternative download methods:"
        log_info "  1. Use SRA Toolkit: fasterq-dump \$accession"
        log_info "  2. Use prefetch + fasterq-dump"
        log_info "  3. Use AWS Open Data: aws s3 cp s3://sra-pub-run-odp/sra/\$accession/\$accession ."
        log_info "  4. Try Aspera download (faster)"
        return 1
    else
        log_info "All downloads complete!"
        return 0
    fi
}

# ==============================================================================
# METHOD 5: NCBI DATASETS (for genomes, annotations, etc.)
# ==============================================================================

download_ncbi_datasets() {
    log_step "METHOD 5: Using NCBI Datasets CLI"
    
    if ! check_command datasets; then
        log_error "Install with: conda install -c conda-forge ncbi-datasets-cli"
        return 1
    fi
    
    local accession=$1
    local download_type=${2:-genome}  # genome, gene, protein
    
    log_info "Searching for: $accession"
    
    # Create output directory named after the accession
    local output_dir="${OUTPUT_DIR}/${accession}"
    mkdir -p "$output_dir"
    
    case $download_type in
        genome)
            log_info "Downloading genome assembly..."
            
            # Download to zip file
            local zip_file="${output_dir}/${accession}_genome.zip"
            
            datasets download genome accession "$accession" \
                --include genome,gff3,gtf,protein,rna,cds,seq-report \
                --filename "$zip_file" || {
                log_error "Failed to download genome for $accession"
                return 1
            }
            
            # Extract directly into the accession folder
            log_info "Extracting files to: $output_dir"
            unzip -q "$zip_file" -d "$output_dir" || {
                log_error "Failed to extract $zip_file"
                return 1
            }
            
            # Optional: Remove the zip file after extraction
            # rm -f "$zip_file"
            
            log_info "✓ Genome download complete!"
            ;;
            
        gene)
            log_info "Downloading gene data..."
            
            local zip_file="${output_dir}/${accession}_genes.zip"
            
            datasets download gene accession "$accession" \
                --filename "$zip_file" || {
                log_error "Failed to download gene data for $accession"
                return 1
            }
            
            log_info "Extracting files to: $output_dir"
            unzip -q "$zip_file" -d "$output_dir" || {
                log_error "Failed to extract $zip_file"
                return 1
            }
            
            # Optional: Remove the zip file after extraction
            # rm -f "$zip_file"
            
            log_info "✓ Gene download complete!"
            ;;
            
        protein)
            log_info "Downloading protein data..."
            
            local zip_file="${output_dir}/${accession}_protein.zip"
            
            datasets download genome accession "$accession" \
                --include protein \
                --filename "$zip_file" || {
                log_error "Failed to download protein data for $accession"
                return 1
            }
            
            log_info "Extracting files to: $output_dir"
            unzip -q "$zip_file" -d "$output_dir" || {
                log_error "Failed to extract $zip_file"
                return 1
            }
            
            # Optional: Remove the zip file after extraction
            # rm -f "$zip_file"
            
            log_info "✓ Protein download complete!"
            ;;
            
        *)
            log_error "Unknown download type: $download_type"
            log_info "Valid types: genome, gene, protein"
            return 1
            ;;
    esac
    
    log_info "All files extracted to: $output_dir"
    log_info ""
    log_info "Directory structure:"
    tree -L 2 "$output_dir" 2>/dev/null || ls -lh "$output_dir"
    
    return 0
}

# ==============================================================================
# NEW: SEARCH NCBI ASSEMBLIES BY ORGANISM NAME
# ==============================================================================

search_ncbi_assemblies() {
    log_step "Searching NCBI Assemblies"
    
    if ! check_command datasets; then
        log_error "Install with: conda install -c conda-forge ncbi-datasets-cli"
        return 1
    fi
    
    if ! check_command jq; then
        log_error "jq not found. Install with: conda install -c conda-forge jq"
        return 1
    fi
    
    local organism=$1
    local output_file="${2:-${OUTPUT_DIR}/assembly_list.txt}"
    local filter=${3:-all}  # all, reference, representative
    
    if [[ -z "$organism" ]]; then
        log_error "Please provide an organism name"
        log_info "Usage: search_ncbi_assemblies \"Mus musculus\" [output_file] [filter]"
        log_info "Filters: all, reference, representative"
        return 1
    fi
    
    log_info "Searching for assemblies of: $organism"
    log_info "Filter: $filter"
    
    # Create temporary file for JSON output
    local temp_json="${TEMP_DIR}/assemblies.json"
    
    # Build the datasets command based on filter
    local datasets_cmd="datasets summary genome taxon \"$organism\""
    
    case $filter in
        reference)
            datasets_cmd="$datasets_cmd --reference"
            ;;
        representative)
            datasets_cmd="$datasets_cmd --assembly-source RefSeq"
            ;;
        all)
            # No additional filter
            ;;
        *)
            log_error "Unknown filter: $filter"
            log_info "Valid filters: all, reference, representative"
            return 1
            ;;
    esac
    
    # Execute the search
    log_info "Fetching assembly data..."
    eval "$datasets_cmd" > "$temp_json" 2>/dev/null || {
        log_error "Failed to search for assemblies"
        log_error "Make sure the organism name is correct"
        return 1
    }
    
    # Check if we got results
    if ! jq -e '.reports' "$temp_json" &>/dev/null; then
        log_error "No assemblies found for: $organism"
        log_info "Try different search terms or check spelling"
        return 1
    fi
    
    # Count total assemblies
    local total_count=$(jq '.reports | length' "$temp_json" 2>/dev/null || echo 0)
    
    if [[ $total_count -eq 0 ]]; then
        log_error "No assemblies found for: $organism"
        return 1
    fi
    
    log_info "Found $total_count assembly/assemblies"
    log_info ""
    
    # Create detailed summary file
    local summary_file="${output_file%.txt}_summary.tsv"
    
    # Extract assembly information with more details
    echo -e "Accession\tOrganism\tAssembly_Name\tLevel\tRelease_Date\tRefSeq_Category" > "$summary_file"
    
    jq -r '.reports[] | 
        [
            .accession,
            .organism.organism_name,
            .assembly_info.assembly_name,
            .assembly_info.assembly_level,
            .assembly_info.release_date,
            (.assembly_info.refseq_category // "N/A")
        ] | @tsv' "$temp_json" >> "$summary_file" || {
        log_error "Failed to parse assembly data"
        return 1
    }
    
    # Extract just the accessions to a simple list
    jq -r '.reports[].accession' "$temp_json" > "$output_file"
    
    log_info "Assembly Summary:"
    log_info "----------------"
    
    # Display the summary in a formatted way
    column -t -s $'\t' "$summary_file" | head -n 20
    
    if [[ $total_count -gt 19 ]]; then
        echo ""
        log_info "... and $((total_count - 19)) more assemblies"
    fi
    
    log_info ""
    log_info "✓ Results saved to:"
    log_info "  Accession list: $output_file"
    log_info "  Detailed summary: $summary_file"
    
    # Highlight reference/representative genomes if present
    local ref_count=$(jq '[.reports[] | select(.assembly_info.refseq_category == "reference genome")] | length' "$temp_json" 2>/dev/null || echo 0)
    local repr_count=$(jq '[.reports[] | select(.assembly_info.refseq_category == "representative genome")] | length' "$temp_json" 2>/dev/null || echo 0)
    
    if [[ $ref_count -gt 0 ]]; then
        log_info ""
        log_info "📌 Reference genomes found: $ref_count"
        jq -r '.reports[] | select(.assembly_info.refseq_category == "reference genome") | 
            "  • " + .accession + " - " + .assembly_info.assembly_name' "$temp_json"
    fi
    
    if [[ $repr_count -gt 0 ]]; then
        log_info ""
        log_info "📌 Representative genomes found: $repr_count"
        jq -r '.reports[] | select(.assembly_info.refseq_category == "representative genome") | 
            "  • " + .accession + " - " + .assembly_info.assembly_name' "$temp_json"
    fi
    
    # Cleanup
    rm -f "$temp_json"
    
    return 0
}

# ==============================================================================
# NEW: SEARCH AND DOWNLOAD ASSEMBLY
# ==============================================================================

search_and_download_assembly() {
    log_step "Search and Download Assembly"
    
    local organism=$1
    local filter=${2:-reference}
    
    if [[ -z "$organism" ]]; then
        log_error "Please provide an organism name"
        return 1
    fi
    
    # Search for assemblies
    local temp_list="${TEMP_DIR}/assembly_accessions.txt"
    search_ncbi_assemblies "$organism" "$temp_list" "$filter" || return 1
    
    # Count results
    local count=$(wc -l < "$temp_list")
    
    if [[ $count -eq 0 ]]; then
        log_error "No assemblies found"
        return 1
    elif [[ $count -eq 1 ]]; then
        # Only one assembly - download it automatically
        local accession=$(cat "$temp_list")
        log_info ""
        log_info "Downloading assembly: $accession"
        download_ncbi_datasets "$accession" genome
    else
        # Multiple assemblies - ask user to choose
        log_info ""
        log_info "Multiple assemblies found. Please choose one:"
        log_info ""
        
        local i=1
        while IFS= read -r accession; do
            echo "  $i) $accession"
            ((i++))
        done < "$temp_list"
        
        echo ""
        read -p "Enter number to download (or 'all' for all assemblies): " choice
        
        if [[ "$choice" == "all" ]]; then
            log_info "Downloading all assemblies..."
            while IFS= read -r accession; do
                log_info ""
                download_ncbi_datasets "$accession" genome
            done < "$temp_list"
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $count ]]; then
            local accession=$(sed -n "${choice}p" "$temp_list")
            log_info ""
            log_info "Downloading assembly: $accession"
            download_ncbi_datasets "$accession" genome
        else
            log_error "Invalid choice"
            return 1
        fi
    fi
    
    return 0
}

# ==============================================================================
# METHOD 6: GEO SUPPLEMENTARY FILES
# ==============================================================================

download_geo_supplementary() {
    log_step "METHOD 6: Downloading GEO Supplementary Files"
    
    local geo_accession=$1
    
    log_info "Downloading supplementary files for $geo_accession..."
    
    # Construct GEO FTP URL
    local series_stub=$(echo "$geo_accession" | sed 's/\(GSE[0-9]*\)[0-9]\{3\}$/\1nnn/')
    local ftp_base="https://ftp.ncbi.nlm.nih.gov/geo/series/${series_stub}/${geo_accession}/suppl/"
    
    log_info "FTP location: $ftp_base"
    
    # Create output directory
    mkdir -p "${OUTPUT_DIR}/metadata/${geo_accession}"
    
    # Download file listing
    wget -q -O "${TEMP_DIR}/file_list.html" "$ftp_base" || {
        log_error "Could not access GEO FTP site"
        return 1
    }
    
    # Parse HTML to get file names
    grep -o 'href="[^"]*"' "${TEMP_DIR}/file_list.html" | \
        sed 's/href="//;s/"$//' | \
        grep -v '^\.\.' | \
        grep -v '^/' | \
        while IFS= read -r filename; do
            
            [[ -z "$filename" ]] && continue
            
            log_info "  Downloading: $filename"
            wget -c -q --show-progress \
                -P "${OUTPUT_DIR}/metadata/${geo_accession}" \
                "${ftp_base}${filename}"
        done
    
    log_info "✓ Download complete!"
    log_info "Files saved to: ${OUTPUT_DIR}/metadata/${geo_accession}/"
}

# ==============================================================================
# UTILITY: CREATE SRR LIST FROM GEO
# ==============================================================================

create_srr_list_from_geo() {
    log_step "Creating SRR list from GEO accession using ffq"
    
    local geo_accession=$1
    local output_file="${2:-SRR_list.txt}"
    
    # Check if ffq is installed
    if ! check_command ffq; then
        log_error "ffq not found. Install with: pip install ffq"
        return 1
    fi
    
    log_info "Fetching SRA information for $geo_accession using ffq..."
    
    # Create temporary files
    local temp_output="${TEMP_DIR}/${geo_accession}_ffq_raw.txt"
    local temp_srr="${TEMP_DIR}/temp_srr.txt"
    
    # Run ffq and capture all output
    # We'll parse the SRR accessions directly from the log output since that's where they appear
    ffq --ftp "$geo_accession" > "$temp_output" 2>&1 || {
        log_error "Failed to fetch data for $geo_accession"
        cat "$temp_output"
        return 1
    }
    
    log_info "Extracting SRR accessions from ffq output..."
    
    # Extract SRR accessions directly from the log lines
    # Look for lines like "INFO Parsing run SRR36693230"
    grep -oP 'Parsing run \K(SRR|ERR|DRR)\d+' "$temp_output" | sort -u > "$temp_srr"
    
    # If that didn't work, try alternative patterns
    if [[ ! -s "$temp_srr" ]]; then
        log_info "Trying alternative extraction method..."
        grep -oE '(SRR|ERR|DRR)[0-9]+' "$temp_output" | sort -u > "$temp_srr"
    fi
    
    # Check if we got any results
    if [[ ! -s "$temp_srr" ]]; then
        log_error "No SRR accessions found for $geo_accession"
        log_error "This GEO entry might not have sequencing data in SRA"
        log_info "Debug: ffq output:"
        cat "$temp_output"
        rm -f "$temp_srr" "$temp_output"
        return 1
    fi
    
    # Copy to final output file
    cp "$temp_srr" "$output_file"
    
    local count=$(wc -l < "$output_file")
    log_info "✓ Found $count SRR accession(s)"
    log_info "Saved to: $output_file"
    
    # Show first few accessions as preview
    if [[ $count -gt 0 ]]; then
        log_info "Preview (first 5):"
        head -n 5 "$output_file" | while read -r srr; do
            echo "  - $srr"
        done
        [[ $count -gt 5 ]] && echo "  ... and $((count - 5)) more"
    fi
    
    # Save the full ffq output for reference
    local log_output="${output_file%.txt}_ffq_log.txt"
    cp "$temp_output" "$log_output"
    log_info "Full ffq output saved to: $log_output"
    
    # Cleanup
    rm -f "$temp_srr" "$temp_output"
    
    return 0
}

# ==============================================================================
# MAIN MENU
# ==============================================================================

show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

COMMANDS:
    sra-fast            Download using fasterq-dump (fast, single-threaded per file)
    sra-prefetch        Download using prefetch + fasterq-dump (robust)
    sra-parallel        Download using parallel-fastq-dump (fastest)
    ena                 Download from ENA (often faster than SRA)
    ncbi-genome         Download genome from NCBI Datasets by accession
    ncbi-search         Search for assemblies by organism name
    ncbi-search-dl      Search and download assemblies by organism name
    geo-suppl           Download GEO supplementary files
    geo-to-srr          Convert GEO accession to SRR list
    
OPTIONS:
    -i FILE         Input file with accession numbers (one per line)
    -o DIR          Output directory (default: downloads)
    -t THREADS      Number of threads (default: 8)
    -g GEO_ID       GEO accession (e.g., GSE280953)
    -s ORGANISM     Organism name for NCBI Datasets

EXAMPLES:
    # Download from SRA using fasterq-dump
    $0 sra-fast -i SRR_list.txt -t 16
    
    # Download from ENA (often faster)
    $0 ena -i SRR_list.txt
    
    # Download using parallel-fastq-dump
    $0 sra-parallel -i SRR_list.txt -t 16
    
    # Create SRR list from GEO
    $0 geo-to-srr -g GSE280953
    
    # Download GEO supplementary files
    $0 geo-suppl -g GSE280953
    
    # Download mouse reference genome
    $0 ncbi-genome -s "Mus musculus"

EOF
}

# ==============================================================================
# PARSE COMMAND LINE ARGUMENTS
# ==============================================================================

if [[ $# -eq 0 ]]; then
    show_usage
    exit 0
fi

COMMAND=$1
shift

# Parse options
while getopts "i:o:t:g:s:h" opt; do
    case $opt in
        i) ACCESSION_LIST="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        g) GEO_ACCESSION="$OPTARG" ;;
        s) ORGANISM="$OPTARG" ;;
        h) show_usage; exit 0 ;;
        *) show_usage; exit 1 ;;
    esac
done

# Create directories
create_dirs

# Execute command
case $COMMAND in
    sra-fast)
        [[ -z "${ACCESSION_LIST:-}" ]] && { log_error "Missing -i option"; exit 1; }
        download_sra_fasterq "$ACCESSION_LIST"
        ;;
    
    sra-prefetch)
        [[ -z "${ACCESSION_LIST:-}" ]] && { log_error "Missing -i option"; exit 1; }
        download_sra_prefetch "$ACCESSION_LIST"
        ;;
    
    sra-parallel)
        [[ -z "${ACCESSION_LIST:-}" ]] && { log_error "Missing -i option"; exit 1; }
        download_parallel_fastq "$ACCESSION_LIST"
        ;;
    
    ena)
        [[ -z "${ACCESSION_LIST:-}" ]] && { log_error "Missing -i option"; exit 1; }
        download_ena "$ACCESSION_LIST"
        ;;
    
    ncbi-genome)
        [[ -z "${ORGANISM:-}" ]] && { log_error "Missing -s option"; exit 1; }
        download_ncbi_datasets "$ORGANISM" "genome"
        ;;

    ncbi-search)
    [[ -z "${ORGANISM:-}" ]] && { log_error "Missing -s option"; exit 1; }
    search_ncbi_assemblies "$ORGANISM"
    ;;
    
    ncbi-search-dl)
    [[ -z "${ORGANISM:-}" ]] && { log_error "Missing -s option"; exit 1; }
    search_and_download_assembly "$ORGANISM"
    ;;
    
    geo-suppl)
        [[ -z "${GEO_ACCESSION:-}" ]] && { log_error "Missing -g option"; exit 1; }
        download_geo_supplementary "$GEO_ACCESSION"
        ;;
    
    geo-to-srr)
        [[ -z "${GEO_ACCESSION:-}" ]] && { log_error "Missing -g option"; exit 1; }
        create_srr_list_from_geo "$GEO_ACCESSION"
        ;;
    
    *)
        log_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac

log_step "DONE!"