#!/usr/bin/env bash

# set -euo pipefail  # Remove or comment this line

# -----------------------------
# Setup
# -----------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
BASE_DIR="$(dirname "$SCRIPT_PATH")"

# Core
source "$BASE_DIR/lib/config.sh"
source "$BASE_DIR/lib/logging.sh"
source "$BASE_DIR/lib/validation.sh"

# Commands

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
    bp-srr        Extract SRA run accessions from BioProjects

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

    ┌─────────────────────────────────────────────────────────────────────────┐
    │ ORTHOLOG DOWNLOADS                                                      │
    └─────────────────────────────────────────────────────────────────────────┘

      --ortholog ACC[,ACC,...]   Comma-separated accessions or Gene IDs
      --ortholog-file FILE       File with one accession/Gene ID per line

      Accepted accession formats:
          NP_/XP_/WP_  - RefSeq protein accessions
          NM_/XM_/NG_  - RefSeq nucleotide accessions
          numeric      - NCBI Gene IDs
      Each is resolved to a Gene ID via NCBI Entrez, then all known
      orthologs for that gene are downloaded as a deduplicated protein
      FASTA. Coverage is vertebrates and insects only (NCBI Datasets
      limitation); a raw result landing right around ~499 records may be
      truncated - a warning is printed when that happens.

      Examples:
        # Single accession
        seqfetcher download --ortholog NP_001416352.1

        # Multiple accessions/Gene IDs
        seqfetcher download --ortholog NP_001416352.1,672

        # From file, 8 in parallel
        seqfetcher download --ortholog-file genes.txt --jobs 8

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

BP-SRR COMMAND

    Extract SRA run accessions (SRR) from a BioProject accession for downstream analysis.

    seqfetcher bp-srr --bioproject PRJNAXXXXXX [options]

    Options:
      --bioproject PRJNAXXXXXX         BioProject accession (required)
      --out FILE             Output filename (default: SRR_list.txt)
      --outdir DIR           Output directory (default: downloads)

    Examples:
      # Extract SRR list to default file
      seqfetcher bp-srr --bioproject PRJNA175224

      # Extract to custom file
      seqfetcher bp-srr --bioproject PRJNA175224 --out my_runs.txt

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
# Main entry
#==============================================================
main() {
    local cmd="${1:-}"

    if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall_seqfetcher
    exit 0
    fi

    case "$cmd" in
        ""|-h|--help)
            show_help
            exit 0
            ;;
        search)
            shift
            commands_search::run_search "$@"
            ;;
        download)
            shift
            commands_download::run_download "$@"
            ;;
        geo-srr)
            shift
            commands_geo_srr::run_geo_srr "$@"
            ;;
        bp-srr)
            shift
            commands_bioproject_srr::run_bioproject_srr "$@"
            ;;
        *)
            echo "Unknown command: $cmd" >&2
            echo >&2
            show_help
            exit 1
            ;;
    esac
}

main "$@"
