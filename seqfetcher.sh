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
source "$BASE_DIR/lib/manifest.sh"

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
    sed "s/__SEQFETCHER_VERSION__/${SEQFETCHER_VERSION:-1.1.0}/" <<'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                       SeqFetcher __SEQFETCHER_VERSION__                     ║
║              Unified Sequence Retrieval from Multiple Databases            ║
╚════════════════════════════════════════════════════════════════════════════╝

USAGE
    seqfetcher [global options] <command> [options]

COMMANDS
    search        Search for genome assemblies in NCBI
    download      Download sequences from various databases
    geo-srr       Extract SRA run accessions from GEO series
    bp-srr        Extract SRA run accessions from BioProjects
    sra-info      Fetch the SRA runinfo table for any SRA/BioProject accession

GLOBAL OPTIONS (before the command)
    --json                Emit a machine-readable result object on stdout
                          (all logs go to stderr - `... --json 2>/dev/null`)
    --quiet, -q           Silence [INFO]/[STEP]/[SUCCESS] progress
    --no-color            Disable ANSI colour
    --force               Re-download even if the lockfile already has it
    --require-pinned      Refuse a source that would resolve to "latest"
    --version             Print the version and exit

EXIT CODES
    0 ok   2 usage   3 missing dependency   4 not found
    5 network   6 checksum mismatch   7 partial (some batch items failed)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SEARCH COMMAND

    Discover what's available before downloading. Three modes: NCBI assemblies
    (default), RCSB PDB structures (--pdb), AlphaFold models (--alphafold).
    Each writes a ranked <outdir>/tables/*.tsv plus an id/accession list that
    feeds straight into a download command.

    seqfetcher search --organism "NAME" [options]                 # assemblies
    seqfetcher search --pdb       [filters] [options]             # RCSB PDB
    seqfetcher search --alphafold [filters] [options]             # AlphaFold

    Common options:
      --top N                Number of top-ranked results (default: 50)
      --outdir DIR           Output directory (default: downloads)
      --output FILE          Custom output table path
      --interactive, -i      Pick rows from the table and download them now

    Assemblies:
      --organism "NAME"      Organism name (required)
      --extract-genes        Extract gene IDs from the reference genome instead

    --pdb filters (need at least one of --organism / --text / --uniprot / --ligand):
      --text "STRING"        Full-text search
      --organism "NAME"      Source organism (exact match)
      --uniprot ACC[,ACC]    Structures referencing these UniProt accessions
      --ligand ID[,ID]       Structures containing these chemical components
      --method x-ray|em|nmr  Experimental method
      --max-resolution N     Resolution <= N Angstrom
      --min-chains N         At least N protein chains
      --after-date / --before-date YYYY-MM-DD    Release-date window
      --sort resolution|date|score               (default: relevance score)

    --alphafold filters (need at least one of --organism / --taxon-id / --text
                         / --gene / --keyword / --proteome):
      --organism "NAME" | --taxon-id N     Species
      --gene NAME            UniProt gene name
      --keyword KW           UniProt keyword (KW-id or word)
      --proteome UPXXXXXXXXX UniProt reference proteome
      --text "STRING"        Free-text UniProt query
      --reviewed             Swiss-Prot entries only
      --check-alphafold      Verify each model exists; add version + mean pLDDT

    Examples:
      seqfetcher search --organism "Escherichia coli"
      seqfetcher search --organism "Homo sapiens" --top 200 --interactive
      seqfetcher search --organism "Mus musculus" --extract-genes

      seqfetcher search --pdb --uniprot P04637
      seqfetcher search --pdb --organism "Homo sapiens" --method x-ray --max-resolution 1.5 --sort resolution
      seqfetcher search --pdb --uniprot P04637 --top 5 \
        && seqfetcher download --structure --pdb-file downloads/tables/pdb_structures_ids.txt

      seqfetcher search --alphafold --organism "Saccharomyces cerevisiae" --reviewed
      seqfetcher search --alphafold --gene TP53 --check-alphafold
      seqfetcher search --alphafold --proteome UP000005640 --top 5000 \
        && seqfetcher download --structure --alphafold-file downloads/tables/alphafold_structures_accessions.txt

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
    │ ANNOTATION-ONLY DOWNLOADS (GFF3/GTF, no genome FASTA)                    │
    └─────────────────────────────────────────────────────────────────────────┘

      --annotation                 Fetch annotation only for --accession(-file)
      --annotation-formats LIST    Comma-separated: gff3,gtf,gbff (default: gff3,gtf)

      Example:
        seqfetcher download --annotation --accession GCF_000009045.1
        seqfetcher download --annotation --accession-file accs.txt --annotation-formats gff3

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
          auto     - Try NCBI then Ensembl
          uniprot  - UniProt (needs --proteome-id)
      --proteome-id UPXXXXXXXXX  UniProt proteome id (implies --source uniprot)
      --type TYPE                Protein type (default: pep)

      Examples:
        # Download from assembly
        seqfetcher download --proteome --assembly GCF_000001405.40

        # Download from species
        seqfetcher download --proteome --species drosophila_melanogaster

        # Download a whole UniProt reference proteome (one gzipped FASTA)
        seqfetcher download --proteome --proteome-id UP000005640

    ┌─────────────────────────────────────────────────────────────────────────┐
    │ STRUCTURE DOWNLOADS (AlphaFold / RCSB PDB)                              │
    └─────────────────────────────────────────────────────────────────────────┘

      --structure                Enable structure download
      --alphafold ACC[,ACC,...]  AlphaFold models by UniProt accession
      --alphafold-file FILE      File with one UniProt accession per line
      --pdb ID[,ID,...]          RCSB PDB structures by 4-char PDB id
      --pdb-file FILE            File with one PDB id per line
      --format FMT               pdb (default) or cif

      Examples:
        seqfetcher download --structure --alphafold P04637,P0DP23 --format cif
        seqfetcher download --structure --pdb 1TUP,4HHB

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

SRA-INFO COMMAND

    Fetch the SRA runinfo table (library, instrument, spots, BioSample
    metadata - one row per run) for any SRA-resolvable accession, without
    downloading the reads.

    seqfetcher sra-info --accession <ACC[,ACC...]> [options]
    seqfetcher sra-info --accession-file <file> [options]

    Accepts SRR/ERR/DRR, SRX, SRP/ERP/DRP and BioProject (PRJNA/PRJEB/PRJDB).

    Options:
      --accession ACC[,ACC,...]   One or more accessions (required unless --accession-file)
      --accession-file FILE       File with one accession per line
      --out FILE                  Run-list filename (default: sra_runinfo_runs.txt)
      --outdir DIR                Output directory (default: downloads)

    Outputs under <outdir>/tables/: sra_runinfo.tsv + sra_runinfo_runs.txt

    Examples:
      seqfetcher sra-info --accession SRP012482
      seqfetcher sra-info --accession PRJNA231221 --out runs.txt

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
# Global option pre-parse
#
# Options that apply to every command are consumed here (in any position)
# and the rest is handed to the per-command parser untouched.
#==============================================================
parse_global_options() {
    GLOBAL_REMAINING=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)          JSON_OUTPUT=true ;;
            --quiet|-q)      QUIET=true ;;
            --no-color)      NO_COLOR=1 ;;
            --force)         FORCE=true ;;
            --require-pinned) REQUIRE_PINNED=true ;;
            --version)       echo "seqfetcher ${SEQFETCHER_VERSION:-unknown}"; exit "${EX_OK:-0}" ;;
            *)               GLOBAL_REMAINING+=("$1") ;;
        esac
        shift
    done
    # colour depends on NO_COLOR, which we may have just set - re-source logging
    source "$BASE_DIR/lib/logging.sh"
}

#==============================================================
# Main entry
#==============================================================
main() {
    if [[ "${1:-}" == "--uninstall" ]]; then
        uninstall_seqfetcher
        exit 0
    fi

    parse_global_options "$@"
    set -- "${GLOBAL_REMAINING[@]}"

    local cmd="${1:-}"
    local rc=0

    case "$cmd" in
        ""|-h|--help)
            show_help
            exit "${EX_OK:-0}"
            ;;
        search)
            shift
            commands_search::run_search "$@" || rc=$?
            ;;
        download)
            shift
            commands_download::run_download "$@" || rc=$?
            ;;
        geo-srr)
            shift
            commands_geo_srr::run_geo_srr "$@" || rc=$?
            ;;
        bp-srr)
            shift
            commands_bioproject_srr::run_bioproject_srr "$@" || rc=$?
            ;;
        sra-info)
            shift
            commands_sra_info::run_sra_info "$@" || rc=$?
            ;;
        *)
            die "Unknown command: $cmd" "${EX_USAGE:-2}"
            ;;
    esac

    exit "$rc"
}

main "$@"
