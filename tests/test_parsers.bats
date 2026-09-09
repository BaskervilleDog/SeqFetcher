#!/usr/bin/env bats
# Unit tests for lib/parsers/search.sh and lib/parsers/download.sh
#
# Only exercises the option-setting branches - the --help/-h and
# unknown-option branches call the real seqfetcher.sh's show_help (stubbed
# in test_helper.bash) and exit 0/1, which is covered by tests/test_cli.bats
# against the real binary instead.

load 'test_helper'

setup() {
    reset_config
}

@test "parsers_search::parse_search_arguments sets ORGANISM" {
    parsers_search::parse_search_arguments --organism "Homo sapiens"
    [ "$ORGANISM" = "Homo sapiens" ]
}

@test "parsers_search::parse_search_arguments sets INTERACTIVE and EXTRACT_GENES flags" {
    parsers_search::parse_search_arguments --organism "E. coli" --interactive --extract-genes
    [ "$INTERACTIVE" = true ]
    [ "$EXTRACT_GENES" = true ]
}

@test "parsers_search::parse_search_arguments -i is a shorthand for --interactive" {
    parsers_search::parse_search_arguments --organism "E. coli" -i
    [ "$INTERACTIVE" = true ]
}

@test "parsers_search::parse_search_arguments --top sets TOP_N" {
    parsers_search::parse_search_arguments --organism "E. coli" --top 200
    [ "$TOP_N" = 200 ]
}

@test "parsers_search::parse_search_arguments TOP_N defaults to 50" {
    parsers_search::parse_search_arguments --organism "E. coli"
    [ "$TOP_N" = 50 ]
}

@test "parsers_search::parse_search_arguments sets custom OUTDIR and OUTPUT_FILE" {
    parsers_search::parse_search_arguments --organism "E. coli" --outdir mydir --output myfile.tsv
    [ "$OUTDIR" = "mydir" ]
    [ "$OUTPUT_FILE" = "myfile.tsv" ]
}

@test "parsers_search::parse_search_arguments --pdb sets MODE and PDB filters" {
    parsers_search::parse_search_arguments --pdb --organism "Homo sapiens" \
        --method x-ray --max-resolution 2.0 --uniprot P04637 --sort resolution
    [ "$MODE" = "pdb" ]
    [ "$SEARCH_METHOD" = "x-ray" ]
    [ "$SEARCH_MAX_RESOLUTION" = "2.0" ]
    [ "$SEARCH_UNIPROT" = "P04637" ]
    [ "$SEARCH_SORT" = "resolution" ]
}

@test "parsers_search::parse_search_arguments --alphafold sets MODE and AF filters" {
    parsers_search::parse_search_arguments --alphafold --gene TP53 --keyword kinase \
        --taxon-id 9606 --reviewed --check-alphafold
    [ "$MODE" = "alphafold" ]
    [ "$SEARCH_GENE" = "TP53" ]
    [ "$SEARCH_KEYWORD" = "kinase" ]
    [ "$SEARCH_TAXON_ID" = "9606" ]
    [ "$SEARCH_REVIEWED" = true ]
    [ "$CHECK_ALPHAFOLD" = true ]
}

@test "parsers_download::parse_download_arguments --accession sets DOWNLOAD_TYPE=assembly" {
    parsers_download::parse_download_arguments --accession GCF_000005845.2
    [ "$ACCESSION" = "GCF_000005845.2" ]
    [ "$DOWNLOAD_TYPE" = "assembly" ]
}

@test "parsers_download::parse_download_arguments --gene-id sets DOWNLOAD_TYPE=gene and GENE_ID_USER" {
    parsers_download::parse_download_arguments --gene-id 945803,944742
    [ "$GENE_ID" = "945803,944742" ]
    [ "$GENE_ID_USER" = true ]
    [ "$DOWNLOAD_TYPE" = "gene" ]
}

@test "parsers_download::parse_download_arguments --sra-method sets DOWNLOAD_TYPE=sra" {
    parsers_download::parse_download_arguments --sra-method fasterq --sra-accession SRR12345678
    [ "$SRA_METHOD" = "fasterq" ]
    [ "$ACCESSION" = "SRR12345678" ]
    [ "$DOWNLOAD_TYPE" = "sra" ]
}

@test "parsers_download::parse_download_arguments --species fans out to all three species vars" {
    parsers_download::parse_download_arguments --transcriptome --species homo_sapiens
    [ "$ENSEMBL_SPECIES" = "homo_sapiens" ]
    [ "$TRANSCRIPTOME_SPECIES" = "homo_sapiens" ]
    [ "$PROTEOME_SPECIES" = "homo_sapiens" ]
}

@test "parsers_download::parse_download_arguments --jobs sets PARALLEL_JOBS" {
    parsers_download::parse_download_arguments --accession GCF_000005845.2 --jobs 8
    [ "$PARALLEL_JOBS" = 8 ]
}

@test "parsers_download::parse_download_arguments --ortholog sets DOWNLOAD_TYPE=ortholog and ORTHOLOG_USER" {
    parsers_download::parse_download_arguments --ortholog NP_001416352.1,672
    [ "$ORTHOLOG" = "NP_001416352.1,672" ]
    [ "$ORTHOLOG_USER" = true ]
    [ "$DOWNLOAD_TYPE" = "ortholog" ]
}

@test "parsers_download::parse_download_arguments --ortholog-file sets DOWNLOAD_TYPE=ortholog and ORTHOLOG_FILE_USER" {
    parsers_download::parse_download_arguments --ortholog-file genes.txt
    [ "$ORTHOLOG_FILE" = "genes.txt" ]
    [ "$ORTHOLOG_FILE_USER" = true ]
    [ "$DOWNLOAD_TYPE" = "ortholog" ]
}

@test "parsers_download::parse_download_arguments --annotation wins over --accession regardless of order" {
    parsers_download::parse_download_arguments --accession GCF_000009045.1 --annotation --annotation-formats gff3
    [ "$DOWNLOAD_TYPE" = "annotation" ]
    [ "$ANNOTATION" = true ]
    [ "$ANNOTATION_FORMATS" = "gff3" ]
    [ "$ACCESSION" = "GCF_000009045.1" ]
}

@test "parsers_download::parse_download_arguments --proteome-id implies --source uniprot" {
    parsers_download::parse_download_arguments --proteome-id UP000005640
    [ "$DOWNLOAD_TYPE" = "proteome" ]
    [ "$PROTEOME_SOURCE" = "uniprot" ]
    [ "$PROTEOME_ID" = "UP000005640" ]
}

@test "parsers_download::parse_download_arguments --structure / --alphafold / --pdb / --format" {
    parsers_download::parse_download_arguments --alphafold P04637,P0DP23 --pdb 1TUP --format cif
    [ "$DOWNLOAD_TYPE" = "structure" ]
    [ "$STRUCTURE" = true ]
    [ "$STRUCTURE_ALPHAFOLD" = "P04637,P0DP23" ]
    [ "$STRUCTURE_PDB" = "1TUP" ]
    [ "$STRUCTURE_FORMAT" = "cif" ]
}
