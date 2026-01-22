#!/usr/bin/env bash
# Help and documentation

supports_color() {
    if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null) -ge 8 ]]; then
        return 0
    fi
    return 1
}

# Initialize color variables
if supports_color; then
    HELP_BOLD='\033[1m'
    HELP_DIM='\033[2m'
    HELP_CYAN='\033[0;36m'
    HELP_GREEN='\033[0;32m'
    HELP_YELLOW='\033[1;33m'
    HELP_BLUE='\033[0;34m'
    HELP_NC='\033[0m'
else
    HELP_BOLD=''
    HELP_DIM=''
    HELP_CYAN=''
    HELP_GREEN=''
    HELP_YELLOW=''
    HELP_BLUE=''
    HELP_NC=''
fi

# -------------------------------------------------
# GLOBAL HELP
# -------------------------------------------------

show_help() {
printf "%b" "

${HELP_BOLD}seqfetcher${HELP_NC} v${VERSION} — Unified sequencing data fetcher
${HELP_DIM}Download genomic, transcriptomic and sequencing data from NCBI, ENA and Ensembl${HELP_NC}

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher <command> <subcommand> [options]

${HELP_BOLD}COMMANDS${HELP_NC}
  ${HELP_CYAN}discover${HELP_NC}
    assembly                Search genome assemblies in NCBI

  ${HELP_CYAN}download${HELP_NC}
    genome                  Download genome assemblies
    transcriptome           Download transcriptome (cDNA/RNA)
    proteome                Download proteomes
    fastq                   Download FASTQ from SRA/ENA

  ${HELP_CYAN}convert${HELP_NC}
    geo-srr                 Convert GEO accession to SRR list

  ${HELP_CYAN}check${HELP_NC}
    environment             Check dependencies and tools

${HELP_BOLD}GLOBAL OPTIONS${HELP_NC}
  --outdir DIR              Output directory (default: downloads)
  --threads N               Parallel threads (default: 8)
  --max-retries N           Retry attempts (default: 3)
  --dry-run                 Print commands without running
  --verbose                 Verbose logging
  --help, -h                Show this help
  --version, -v             Show version

${HELP_BOLD}DETAILED HELP${HELP_NC}
  seqfetcher <command> <subcommand> --help

Examples:
  seqfetcher discover assembly --help
  seqfetcher download genome --help
  seqfetcher convert geo-srr --help

"
}

# -------------------------------------------------
# QUICK HELP
# -------------------------------------------------

show_quick_help() {
printf "%b" "
${HELP_BOLD}seqfetcher${HELP_NC} v${VERSION} — Quick Reference

${HELP_BOLD}Common workflows:${HELP_NC}

  Search reference genomes:
    seqfetcher discover assembly --organism "Mus musculus" --filter reference

  Download genome:
    seqfetcher download genome --assembly GCF_000001405.40

  Download transcriptome:
    seqfetcher download transcriptome --species homo_sapiens --source ensembl

  Download proteome:
    seqfetcher download proteome --assembly GCF_000001405.40

  Convert GEO to SRR:
    seqfetcher convert geo-srr --geo GSE280953

  Download FASTQ:
    seqfetcher download fastq --accessions SRR_list.txt --source ena

${HELP_BOLD}Get full help:${HELP_NC}
  seqfetcher --help

"
}

# -------------------------------------------------
# SUBCOMMAND HELP
# -------------------------------------------------

show_subcommand_help() {
    local subcommand=$1

    case "$subcommand" in

# ---------- DISCOVER ----------

"discover:assembly")
printf "%b" "
${HELP_BOLD}seqfetcher discover assembly${HELP_NC}

Search genome assemblies in NCBI Datasets

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher discover assembly --organism "SPECIES" [options]

${HELP_BOLD}REQUIRED${HELP_NC}
  --organism "NAME"        Scientific species name

${HELP_BOLD}OPTIONS${HELP_NC}
  --filter FILTER         all | reference | representative (default: all)
  --out FILE             Output accession list file

${HELP_BOLD}EXAMPLES${HELP_NC}
  seqfetcher discover assembly --organism Homo sapiens
  seqfetcher discover assembly --organism Mus musculus --filter reference

${HELP_BOLD}OUTPUT${HELP_NC}
  • assembly_accessions.txt
  • assembly_accessions_summary.tsv

"
;;

# ---------- DOWNLOAD GENOME ----------

"download:genome")
printf "%b" "
${HELP_BOLD}seqfetcher download genome${HELP_NC}

Download genome assemblies from NCBI Datasets

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher download genome [mode] [options]

${HELP_BOLD}MODES (choose exactly one)${HELP_NC}
  --assembly ACC           Download a single assembly
  --accessions FILE       Batch download from list
  --organism "NAME"       Interactive search + download

${HELP_BOLD}OPTIONS${HELP_NC}
  --include TYPES         genome,cdna,rna,pep,gff,gtf,cds (comma-separated)
  --filter FILTER         reference | representative | all (for --organism)

${HELP_BOLD}EXAMPLES${HELP_NC}
  seqfetcher download genome --assembly GCF_000001405.40
  seqfetcher download genome --assembly GCF_* --include genome,gff,pep
  seqfetcher download genome --organism "Danio rerio" --filter reference

"
;;

# ---------- DOWNLOAD TRANSCRIPTOME ----------

"download:transcriptome")
printf "%b" "
${HELP_BOLD}seqfetcher download transcriptome${HELP_NC}

Download transcriptomes from NCBI or Ensembl

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher download transcriptome [options]

${HELP_BOLD}SOURCES${HELP_NC}
  ncbi        Requires --assembly
  ensembl     Requires --species
  auto        Try NCBI first, fallback to Ensembl

${HELP_BOLD}OPTIONS${HELP_NC}
  --assembly ACC          NCBI assembly accession
  --species NAME         Ensembl species (genus_species)
  --source SOURCE        ncbi | ensembl | auto (default: auto)
  --type TYPE            cdna | cds | ncrna | dna (default: cdna)
  --ensembl-release N    Specific Ensembl release

${HELP_BOLD}EXAMPLES${HELP_NC}
  seqfetcher download transcriptome --assembly GCF_*
  seqfetcher download transcriptome --species homo_sapiens --source ensembl
  seqfetcher download transcriptome --source auto --assembly GCF_* --species mus_musculus

"
;;

# ---------- DOWNLOAD PROTEOME ----------

"download:proteome")
printf "%b" "
${HELP_BOLD}seqfetcher download proteome${HELP_NC}

Download proteomes from NCBI or Ensembl

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher download proteome [options]

${HELP_BOLD}OPTIONS${HELP_NC}
  --assembly ACC          NCBI assembly accession
  --species NAME         Ensembl species (genus_species)
  --source SOURCE        ncbi | ensembl | auto (default: auto)
  --type TYPE            pep (default)

${HELP_BOLD}EXAMPLES${HELP_NC}
  seqfetcher download proteome --assembly GCF_000001405.40
  seqfetcher download proteome --species homo_sapiens --source ensembl
  seqfetcher download proteome --source auto --assembly GCF_* --species mus_musculus

"
;;

# ---------- DOWNLOAD FASTQ ----------

"download:fastq")
printf "%b" "
${HELP_BOLD}seqfetcher download fastq${HELP_NC}

Download RNA-seq FASTQ files from ENA or SRA

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher download fastq --accessions FILE [options]

${HELP_BOLD}REQUIRED${HELP_NC}
  --accessions FILE      File with SRR/ERR/DRR accessions

${HELP_BOLD}OPTIONS${HELP_NC}
  --source SOURCE        ena | sra (default: ena)
  --method METHOD        fasterq | prefetch | parallel (for sra)

${HELP_BOLD}EXAMPLES${HELP_NC}
  seqfetcher download fastq --accessions list.txt
  seqfetcher download fastq --accessions list.txt --source sra --method parallel

${HELP_BOLD}TIP${HELP_NC}
  ENA is recommended for speed and checksum validation

"
;;

# ---------- CONVERT GEO ----------

"convert:geo-srr")
printf "%b" "
${HELP_BOLD}seqfetcher convert geo-srr${HELP_NC}

Convert GEO accession (GSE) into SRR accession list

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher convert geo-srr --geo GSEXXXXX [options]

${HELP_BOLD}REQUIRED${HELP_NC}
  --geo GSEXXXXX          GEO Series accession

${HELP_BOLD}OPTIONS${HELP_NC}
  --out FILE             Output file (default: SRR_list.txt)

${HELP_BOLD}EXAMPLES${HELP_NC}
  seqfetcher convert geo-srr --geo GSE280953
  seqfetcher convert geo-srr --geo GSE280953 --out samples.txt

${HELP_BOLD}NOTES${HELP_NC}
  Uses ffq to query SRA and extract SRR/ERR/DRR accessions

"
;;

# ---------- FALLBACK ----------

*)
    show_help
    ;;
esac
}

# -------------------------------------------------
# VALIDATION HELPERS
# -------------------------------------------------

require_param() {
    local param_name=$1
    local param_value=$2

    if [[ -z "$param_value" ]]; then
        log_error "Missing required parameter: --${param_name}"
        log_info "Run 'seqfetcher ${COMMAND:-} ${SUBCOMMAND:-} --help' for usage"
        exit 1
    fi
}

show_contextual_help() {
    local cmd=$1
    local subcmd=$2

    if [[ -n "$subcmd" ]]; then
        show_subcommand_help "${cmd}:${subcmd}"
    else
        show_help
    fi
}
