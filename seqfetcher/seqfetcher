#!/usr/bin/env bash

# set -euo pipefail  # Remove or comment this line

# -----------------------------
# Setup
# -----------------------------
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load modules
source "$BASE_DIR/lib/logging.sh"
source "$BASE_DIR/lib/validation.sh"
source "$BASE_DIR/lib/ncbi_search.sh"
source "$BASE_DIR/lib/ncbi_download.sh"
source "$BASE_DIR/lib/sra_download.sh"
source "$BASE_DIR/lib/ena_download.sh"
source "$BASE_DIR/lib/geo_download.sh"
source "$BASE_DIR/lib/ensembl_download.sh"

# Export functions for parallel execution
export -f download_assembly
export -f download_assemblies_parallel
export -f download_genes_batches
export -f download_assemblies_interactive
export -f log_info log_error log_step
export -f download_sra_fasterq download_sra_prefetch download_parallel_fastq
export -f download_ena download_ena_worker
export -f download_geo_supplementary create_srr_list_from_geo
export -f validate_sra_accession validate_accession
export BASE_DIR
export OUTPUT_DIR="$output_dir"
export TEMP_DIR="$temp_dir"
export -f log_info log_error log_warning 2>/dev/null || true
export -f get_latest_ensembl_release
export -f download_ensembl_fasta
export -f download_transcriptome
export -f download_proteome

# -----------------------------
# Defaults
# -----------------------------
MODE="assemblies"
ORGANISM=""
OUTDIR="downloads"
OUTPUT_FILE=""
ACCESSION=""
ACCESSION_FILE=""
INTERACTIVE=false
EXTRACT_GENES=false
PARALLEL_JOBS=4
GENE_FILE=""
GENE_FILE_USER=false
GENE_ID=""
GENE_ID_USER=false
DOWNLOAD_TYPE="assembly"  # default
SRA_METHOD=""             # for sra, can be fasterq, prefetch, parallel
GEO_ACCESSION=""
THREADS=4
TEMP_DIR="temp_downloads"
OUTPUT_DIR="$OUTDIR"
DOWNLOAD_TYPE="assembly"
ENSEMBL_FASTA=false
TRANSCRIPTOME=false
PROTEOME=false
ENSEMBL_SPECIES=""
ENSEMBL_TYPE=""
ENSEMBL_RELEASE=""
TRANSCRIPTOME_ASSEMBLY=""
TRANSCRIPTOME_SPECIES=""
TRANSCRIPTOME_SOURCE="ncbi"
TRANSCRIPTOME_TYPE="cdna"
PROTEOME_ASSEMBLY=""
PROTEOME_SPECIES=""
PROTEOME_SOURCE="ncbi"
PROTEOME_TYPE="pep"


#==============================================================
# Help
#==============================================================
show_help() {
    cat <<'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                            SeqFetcher v1.0                                 ║
║              Unified Sequence Retrieval from Multiple Databases            ║
╚════════════════════════════════════════════════════════════════════════════╝

USAGE
    seqfetcher <command> [options]

COMMANDS
    search        Search for genome assemblies in NCBI
    download      Download sequences from various databases
    geo-srr       Extract SRA run accessions from GEO series

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SEARCH COMMAND

    Search for assemblies and extract gene information from NCBI.

    seqfetcher search --organism "ORGANISM_NAME" [options]

    Options:
      --organism "NAME"      Organism name (required)
      --outdir DIR           Output directory (default: downloads)
      --output FILE          Custom output filename
      --interactive, -i      Interactive mode - select assemblies to download
      --extract-genes        Extract gene IDs from reference genome

    Examples:
      # Basic search
      seqfetcher search --organism "Escherichia coli"

      # Search and save to custom directory
      seqfetcher search --organism "Homo sapiens" --outdir human_data

      # Interactive mode - choose which assemblies to download
      seqfetcher search --organism "Saccharomyces cerevisiae" --interactive

      # Extract all gene IDs from reference genome
      seqfetcher search --organism "Drosophila melanogaster" --extract-genes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DOWNLOAD COMMAND

    Download assemblies, genes, transcriptomes, proteomes, or sequencing data.

    seqfetcher download [type-specific options]

    Common Options:
      --outdir DIR           Output directory (default: downloads)
      --jobs, -j NUMBER      Parallel downloads (default: 4)

    ┌─────────────────────────────────────────────────────────────────────────┐
    │ ASSEMBLY DOWNLOADS                                                      │
    └─────────────────────────────────────────────────────────────────────────┘

      --accession ACC        Single assembly accession
      --accession-file FILE  File with one accession per line

      Examples:
        # Download single assembly
        seqfetcher download --accession GCF_000005845.2

        # Download multiple assemblies in parallel
        seqfetcher download --accession-file assemblies.txt --jobs 8

    ┌─────────────────────────────────────────────────────────────────────────┐
    │ GENE DOWNLOADS                                                          │
    └─────────────────────────────────────────────────────────────────────────┘

      --gene-id ID[,ID,...]  Comma-separated gene IDs
      --gene-file FILE       File with one gene ID per line

      Examples:
        # Download single gene
        seqfetcher download --gene-id 12345

        # Download multiple genes
        seqfetcher download --gene-id 12345,67890,11111

        # Download from file
        seqfetcher download --gene-file my_genes.txt --jobs 6

    ┌─────────────────────────────────────────────────────────────────────────┐
    │ SRA DOWNLOADS (Sequencing Reads)                                        │
    └─────────────────────────────────────────────────────────────────────────┘

      --sra-method METHOD         Download method (required)
          fasterq   - SRA Toolkit fasterq-dump
          prefetch  - SRA Toolkit prefetch
          parallel  - Parallel-fastq-dump
          ena       - European Nucleotide Archive

      --sra-accession ACC         Single SRA accession (SRR/ERR/DRR)
      --sra-accession-file FILE   File with accessions

      Examples:
        # Download single run with fasterq-dump
        seqfetcher download --sra-method fasterq --sra-accession SRR12345678

        # Download multiple runs from ENA
        seqfetcher download --sra-method ena --sra-accession-file srr_list.txt

        # Fast parallel download
        seqfetcher download --sra-method parallel --sra-accession-file runs.txt --jobs 4

    ┌─────────────────────────────────────────────────────────────────────────┐
    │ GEO DOWNLOADS (Gene Expression Omnibus)                                 │
    └─────────────────────────────────────────────────────────────────────────┘

      --geo GSEXXXXX         GEO series accession

      Examples:
        # Download supplementary files from GEO series
        seqfetcher download --geo GSE280953

    ┌─────────────────────────────────────────────────────────────────────────┐
    │ ENSEMBL FASTA DOWNLOADS                                                 │
    └─────────────────────────────────────────────────────────────────────────┘

      --ensembl-fasta            Enable Ensembl download
      --species NAME             Species name (required)
      --type TYPE                Sequence type (required)
          cdna   - cDNA sequences
          cds    - Coding sequences
          dna    - Genomic DNA
          ncrna  - Non-coding RNA
          pep    - Peptide sequences
      --release NUMBER           Ensembl release (optional, uses latest)

      Examples:
        # Download human cDNA sequences
        seqfetcher download --ensembl-fasta --species homo_sapiens --type cdna

        # Download mouse proteins from specific release
        seqfetcher download --ensembl-fasta --species mus_musculus \
            --type pep --release 110

    ┌─────────────────────────────────────────────────────────────────────────┐
    │ TRANSCRIPTOME DOWNLOADS                                                 │
    └─────────────────────────────────────────────────────────────────────────┘

      --transcriptome            Enable transcriptome download
      --assembly ACC             Assembly accession (GCF/GCA)
      --species NAME             Species name
      --source SOURCE            Data source (default: ncbi)
          ncbi     - NCBI RefSeq
          ensembl  - Ensembl
          auto     - Try both
      --type TYPE                Transcript type (default: cdna)
          cdna     - cDNA sequences
          cds      - Coding sequences
          ncrna    - Non-coding RNA

      Examples:
        # Download from assembly
        seqfetcher download --transcriptome --assembly GCF_000001405.40

        # Download from species with auto-detection
        seqfetcher download --transcriptome --species homo_sapiens --source auto

        # Download specific type
        seqfetcher download --transcriptome --species mus_musculus \
            --type cds --source ensembl

    ┌─────────────────────────────────────────────────────────────────────────┐
    │ PROTEOME DOWNLOADS                                                      │
    └─────────────────────────────────────────────────────────────────────────┘

      --proteome                 Enable proteome download
      --assembly ACC             Assembly accession (GCF/GCA)
      --species NAME             Species name
      --source SOURCE            Data source (default: ncbi)
          ncbi     - NCBI RefSeq
          ensembl  - Ensembl
          auto     - Try both
      --type TYPE                Protein type (default: pep)

      Examples:
        # Download from assembly
        seqfetcher download --proteome --assembly GCF_000001405.40

        # Download from species
        seqfetcher download --proteome --species drosophila_melanogaster

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

GEO-SRR COMMAND

    Extract SRA run accessions (SRR) from a GEO series for downstream analysis.

    seqfetcher geo-srr --geo GSEXXXXX [options]

    Options:
      --geo GSEXXXXX         GEO series accession (required)
      --out FILE             Output filename (default: SRR_list.txt)
      --outdir DIR           Output directory (default: downloads)

    Examples:
      # Extract SRR list to default file
      seqfetcher geo-srr --geo GSE280953

      # Extract to custom file
      seqfetcher geo-srr --geo GSE280953 --out my_runs.txt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

COMMON WORKFLOWS

    Workflow 1: Complete GEO Analysis Pipeline
    ───────────────────────────────────────────
      # Step 1: Download supplementary files
      seqfetcher download --geo GSE280953

      # Step 2: Extract SRA run accessions
      seqfetcher geo-srr --geo GSE280953 --out runs.txt

      # Step 3: Download sequencing data
      seqfetcher download --sra-method fasterq --sra-accession-file runs.txt

    Workflow 2: Search and Download Assembly
    ─────────────────────────────────────────
      # Step 1: Search for organism
      seqfetcher search --organism "Bacillus subtilis" --output assemblies.tsv

      # Step 2: Download assemblies from results
      seqfetcher download --accession-file assemblies.tsv

    Workflow 3: Extract and Download Genes
    ───────────────────────────────────────
      # Step 1: Extract gene IDs from reference
      seqfetcher search --organism "Mus musculus" --extract-genes

      # Step 2: Download extracted genes
      seqfetcher download --gene-file downloads/gene_ids.txt

    Workflow 4: Multi-Source Transcriptome Download
    ───────────────────────────────────────────────
      # Try NCBI first, then Ensembl
      seqfetcher download --transcriptome --species homo_sapiens --source auto

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

GENERAL OPTIONS
    --help, -h             Show this help message

NOTES
    • All downloads use parallel processing where applicable
    • Temporary files are automatically cleaned up
    • Progress is logged for all operations
    • Failed downloads are reported with details

For more information and updates, visit the project repository.
EOF
}

#==============================================================
# Parse search arguments
#==============================================================
parse_search_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --organism) ORGANISM="$2"; shift 2 ;;
            --mode) MODE="$2"; shift 2 ;;
            --outdir) OUTDIR="$2"; shift 2 ;;
            --output) OUTPUT_FILE="$2"; shift 2 ;;
            --interactive|-i) INTERACTIVE=true; shift ;;
            --extract-genes) EXTRACT_GENES=true; shift ;;
            --help|-h) show_help; exit 0 ;;
            *) log_error "Unknown option for search: $1"; show_help; exit 1 ;;
        esac
    done
}

validate_search_inputs() {
    [[ -z "$ORGANISM" ]] && { log_error "Missing --organism"; show_help; exit 1; }
    [[ "$MODE" != "assemblies" ]] && { log_error "Invalid --mode: $MODE"; exit 1; }

    if [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="${OUTDIR}/assemblies.tsv"
        [[ "$EXTRACT_GENES" == true ]] && OUTPUT_FILE="${OUTDIR}/gene_ids.txt"
    fi
}

execute_search() {
    log_info "Searching for organism: $ORGANISM"
    mkdir -p "$OUTDIR"
    mkdir -p "$TEMP_DIR"
    
    # Trap to ensure cleanup on exit
    trap cleanup_temp EXIT

    if [[ "$EXTRACT_GENES" == true ]]; then
        extract_gene_ids_from_reference "$ORGANISM" "$OUTPUT_FILE" || { log_error "Gene extraction failed"; cleanup_temp; exit 1; }
        cleanup_temp
        return 0
    fi

    search_metadata_by_organism "$ORGANISM" "$OUTDIR/taxonomy_metadata.tsv" || log_warning "Metadata fetch failed"
    search_assemblies_by_organism "$ORGANISM" "$OUTPUT_FILE" || { log_error "Assembly search failed"; cleanup_temp; exit 1; }

    log_info "Results saved to $OUTPUT_FILE"
    [[ "$INTERACTIVE" == true ]] && download_assemblies_interactive "$OUTPUT_FILE" "$OUTDIR"
    
    cleanup_temp
}

#==============================================================
# Parse download arguments
#==============================================================
parse_download_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --accession)
                ACCESSION="$2"; DOWNLOAD_TYPE="assembly"; shift 2 ;;
            --accession-file)
                ACCESSION_FILE="$2"; DOWNLOAD_TYPE="assembly"; shift 2 ;;
            --gene-id)
                GENE_ID="$2"; GENE_ID_USER=true; DOWNLOAD_TYPE="gene"; shift 2 ;;
            --gene-file)
                GENE_FILE="$2"; GENE_FILE_USER=true; DOWNLOAD_TYPE="gene"; shift 2 ;;
            --sra-method)
                SRA_METHOD="$2"; DOWNLOAD_TYPE="sra"; shift 2 ;;
            --sra-accession-file)
                ACCESSION_FILE="$2"; DOWNLOAD_TYPE="sra"; shift 2 ;;
            --sra-accession)
                ACCESSION="$2"; DOWNLOAD_TYPE="sra"; shift 2 ;;
            --geo)
                GEO_ACCESSION="$2"; DOWNLOAD_TYPE="geo"; shift 2 ;;
            --ensembl-fasta)
                ENSEMBL_FASTA=true
                DOWNLOAD_TYPE="ensembl-fasta"
                shift ;;
            --species)
                ENSEMBL_SPECIES="$2"
                TRANSCRIPTOME_SPECIES="$2"
                PROTEOME_SPECIES="$2"
                shift 2 ;;
            --type)
                ENSEMBL_TYPE="$2"
                TRANSCRIPTOME_TYPE="$2"
                PROTEOME_TYPE="$2"
                shift 2 ;;
            --release)
                ENSEMBL_RELEASE="$2"
                shift 2 ;;
            --transcriptome)
                TRANSCRIPTOME=true
                DOWNLOAD_TYPE="transcriptome"
                shift ;;
            --assembly)
                TRANSCRIPTOME_ASSEMBLY="$2"
                PROTEOME_ASSEMBLY="$2"
                shift 2 ;;
            --source)
                TRANSCRIPTOME_SOURCE="$2"
                PROTEOME_SOURCE="$2"
                shift 2 ;;
            --proteome)
                PROTEOME=true
                DOWNLOAD_TYPE="proteome"
                shift ;;
            --outdir)
                OUTDIR="$2"; shift 2 ;;
            --jobs|-j)
                PARALLEL_JOBS="$2"; shift 2 ;;
            --help|-h)
                show_help; exit 0 ;;
            *)
                log_error "Unknown option for download: $1"; show_help; exit 1 ;;
        esac
    done
}

validate_download_inputs() {
    if [[ "$DOWNLOAD_TYPE" == "assembly" ]]; then
        [[ -z "$ACCESSION" && -z "$ACCESSION_FILE" ]] && { log_error "Must specify --accession or --accession-file"; show_help; exit 1; }
        [[ -n "$ACCESSION_FILE" && ! -f "$ACCESSION_FILE" ]] && { log_error "Accession file not found: $ACCESSION_FILE"; exit 1; }
    elif [[ "$DOWNLOAD_TYPE" == "gene" ]]; then
        [[ "$GENE_ID_USER" == false && "$GENE_FILE_USER" == false ]] && { log_error "Must specify --gene-id or --gene-file"; show_help; exit 1; }
        [[ "$GENE_FILE_USER" == true && ! -f "$GENE_FILE" ]] && { log_error "Gene file not found: $GENE_FILE"; exit 1; }
    elif [[ "$DOWNLOAD_TYPE" == "sra" ]]; then
        [[ -z "$SRA_METHOD" ]] && { log_error "Must specify --sra-method"; show_help; exit 1; }
        if [[ -z "$ACCESSION" && -z "$ACCESSION_FILE" ]]; then
            log_error "Must specify --sra-accession or --sra-accession-file"
            show_help; exit 1
        fi
        [[ -n "$ACCESSION_FILE" && ! -f "$ACCESSION_FILE" ]] && { log_error "SRA accession file not found: $ACCESSION_FILE"; exit 1; }
    elif [[ "$DOWNLOAD_TYPE" == "geo" ]]; then
        [[ -z "$GEO_ACCESSION" ]] && { log_error "Must specify --geo GSEXXXXX"; show_help; exit 1; }
    elif [[ "$DOWNLOAD_TYPE" == "ensembl-fasta" ]]; then
        [[ -z "$ENSEMBL_SPECIES" ]] && { log_error "Ensembl FASTA requires --species"; exit 1; }
        [[ -z "$ENSEMBL_TYPE" ]] && { log_error "Ensembl FASTA requires --type"; exit 1; }

    elif [[ "$DOWNLOAD_TYPE" == "transcriptome" ]]; then
        [[ -z "$TRANSCRIPTOME_ASSEMBLY" && -z "$TRANSCRIPTOME_SPECIES" ]] && {
            log_error "Transcriptome requires --assembly or --species"
            exit 1
        }

    elif [[ "$DOWNLOAD_TYPE" == "proteome" ]]; then
        [[ -z "$PROTEOME_ASSEMBLY" && -z "$PROTEOME_SPECIES" ]] && {
            log_error "Proteome requires --assembly or --species"
            exit 1
        }
    fi
    
}

execute_download() {
    mkdir -p "$OUTDIR"
    mkdir -p "$TEMP_DIR"
    
    # Trap to ensure cleanup on exit
    trap cleanup_temp EXIT
    
    if [[ "$DOWNLOAD_TYPE" == "geo" ]]; then
        # Handle GEO supplementary file download
        log_info "Starting GEO supplementary download to: $OUTDIR"
        export OUTPUT_DIR="$OUTDIR"
        export TEMP_DIR
        download_geo_supplementary --geo "$GEO_ACCESSION" --outdir "$OUTDIR"
        local result=$?
        cleanup_temp
        return $result
    fi
    
    log_info "Starting download ($DOWNLOAD_TYPE) to: $OUTDIR (parallel jobs: $PARALLEL_JOBS)"

    if [[ "$DOWNLOAD_TYPE" == "ensembl-fasta" ]]; then
        log_info "Starting Ensembl FASTA download"
        export OUTPUT_DIR TEMP_DIR ENSEMBL_RELEASE

        download_ensembl_fasta \
            "$ENSEMBL_SPECIES" \
            "$ENSEMBL_TYPE" \
            "$OUTDIR"

        cleanup_temp
        return $?
    fi

    if [[ "$DOWNLOAD_TYPE" == "transcriptome" ]]; then
        log_info "Starting transcriptome download"
        export OUTPUT_DIR TEMP_DIR ENSEMBL_TYPE ENSEMBL_RELEASE

        download_transcriptome \
            "$TRANSCRIPTOME_ASSEMBLY" \
            "$TRANSCRIPTOME_SPECIES" \
            "$TRANSCRIPTOME_SOURCE" \
            "$TRANSCRIPTOME_TYPE"

        cleanup_temp
        return $?
    fi

    if [[ "$DOWNLOAD_TYPE" == "proteome" ]]; then
        log_info "Starting proteome download"
        export OUTPUT_DIR TEMP_DIR ENSEMBL_TYPE ENSEMBL_RELEASE

        download_proteome \
            "$PROTEOME_ASSEMBLY" \
            "$PROTEOME_SPECIES" \
            "$PROTEOME_SOURCE" \
            "$PROTEOME_TYPE"

        cleanup_temp
        return $?
    fi

    if [[ "$DOWNLOAD_TYPE" == "assembly" ]]; then
        if [[ -n "$ACCESSION" ]]; then
            download_assembly "$ACCESSION" "$OUTDIR" false
        elif [[ -n "$ACCESSION_FILE" ]]; then
            download_assemblies_parallel "$ACCESSION_FILE" "$OUTDIR" "$PARALLEL_JOBS"
        fi
    elif [[ "$DOWNLOAD_TYPE" == "gene" ]]; then
        [[ "$GENE_ID_USER" == true ]] && tmp=$(mktemp) && echo "$GENE_ID" | tr ',' '\n' > "$tmp" && input="$tmp" || input="$GENE_FILE"
        download_genes_batches "$input" "$OUTDIR" "$PARALLEL_JOBS"
        [[ "$GENE_ID_USER" == true ]] && rm -f "$tmp"
    elif [[ "$DOWNLOAD_TYPE" == "sra" ]]; then
        mkdir -p "$OUTDIR/fastq"

        # Build input file (single accession or file)
        if [[ -n "$ACCESSION" ]]; then
            tmp_sra=$(mktemp)
            echo "$ACCESSION" > "$tmp_sra"
            INPUT_FILE="$tmp_sra"
        else
            INPUT_FILE="$ACCESSION_FILE"
        fi

        export THREADS TEMP_DIR OUTPUT_DIR

        case "$SRA_METHOD" in
            fasterq)  download_sra_fasterq  "$INPUT_FILE" ;;
            prefetch) download_sra_prefetch "$INPUT_FILE" ;;
            parallel) download_parallel_fastq "$INPUT_FILE" ;;
            ena)      download_ena "$INPUT_FILE" ;;
            *) log_error "Unknown SRA method: $SRA_METHOD"
               log_error "Valid methods: fasterq, prefetch, parallel, ena"; exit 1 ;;
        esac

        # Cleanup temp file if created
        [[ -n "${tmp_sra:-}" ]] && rm -f "$tmp_sra"
    fi
    
    cleanup_temp
}

#==============================================================
# GEO Commands
#==============================================================

cleanup_temp() {
    if [[ -d "$TEMP_DIR" ]]; then
        log_info "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

execute_geo_srr() {
    export OUTPUT_DIR="$OUTDIR"
    export TEMP_DIR
    mkdir -p "$TEMP_DIR"
    
    # Trap to ensure cleanup on exit
    trap cleanup_temp EXIT
    
    create_srr_list_from_geo "$@"
    local result=$?
    
    cleanup_temp
    return $result
}

#==============================================================
# Main entry
#==============================================================
main() {
    [[ $# -lt 1 ]] && { log_error "Command required"; show_help; exit 1; }

    CMD="$1"; shift
    echo "DEBUG: Command received: $CMD" >&2
    
    case "$CMD" in
        search)
            parse_search_arguments "$@"
            validate_search_inputs
            execute_search
            ;;
        download)
            parse_download_arguments "$@"
            validate_download_inputs
            execute_download
            ;;
        geo-srr)
            execute_geo_srr "$@"
            ;;
        --help|-h|help)
            show_help; exit 0 ;;
        *)
            log_error "Unknown command: $CMD"; show_help; exit 1 ;;
    esac

    echo "DEBUG: Main function completed" >&2
}

main "$@"
