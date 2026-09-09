#!/usr/bin/env bash

parsers_download::parse_download_arguments() {
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
            --proteome-id)
                PROTEOME_ID="$2"
                PROTEOME=true
                PROTEOME_SOURCE="uniprot"
                DOWNLOAD_TYPE="proteome"
                shift 2 ;;
            --annotation)
                ANNOTATION=true
                DOWNLOAD_TYPE="annotation"
                shift ;;
            --annotation-formats)
                ANNOTATION_FORMATS="$2"; shift 2 ;;
            --structure)
                STRUCTURE=true
                DOWNLOAD_TYPE="structure"
                shift ;;
            --alphafold)
                STRUCTURE_ALPHAFOLD="$2"; STRUCTURE=true; DOWNLOAD_TYPE="structure"; shift 2 ;;
            --alphafold-file)
                STRUCTURE_ALPHAFOLD_FILE="$2"; STRUCTURE=true; DOWNLOAD_TYPE="structure"; shift 2 ;;
            --pdb)
                STRUCTURE_PDB="$2"; STRUCTURE=true; DOWNLOAD_TYPE="structure"; shift 2 ;;
            --pdb-file)
                STRUCTURE_PDB_FILE="$2"; STRUCTURE=true; DOWNLOAD_TYPE="structure"; shift 2 ;;
            --format)
                STRUCTURE_FORMAT="$2"; shift 2 ;;
            --ortholog)
                ORTHOLOG="$2"; ORTHOLOG_USER=true; DOWNLOAD_TYPE="ortholog"; shift 2 ;;
            --ortholog-file)
                ORTHOLOG_FILE="$2"; ORTHOLOG_FILE_USER=true; DOWNLOAD_TYPE="ortholog"; shift 2 ;;
            --outdir)
                OUTDIR="$2"; shift 2 ;;
            --jobs|-j)
                PARALLEL_JOBS="$2"; shift 2 ;;
            --help|-h)
                show_help; exit 0 ;;
            *)
                log_error "Unknown option for download: $1"; show_help; exit "${EX_USAGE:-2}" ;;
        esac
    done

    # --annotation / --structure win regardless of flag order (--accession,
    # --species etc. also set DOWNLOAD_TYPE as a side effect).
    if [[ "$ANNOTATION" == true ]]; then DOWNLOAD_TYPE="annotation"; fi
    if [[ "$STRUCTURE"  == true ]]; then DOWNLOAD_TYPE="structure"; fi
    return 0
}