#!/usr/bin/env bash


# If using WSL and having problems with DNS connection to datasets API:
# 1. Stop WSL from overwriting DNS
# sudo nano /etc/wsl.conf
# Add:
# [network]
# generateResolvConf = false
#
# 2. Replace DNS manually
# sudo rm /etc/resolv.conf
# echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
# echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
#
# 3. Restart WSL fully (From Windows Powershell)
# wsl --shutdown



# Single source of truth for the version string (shown in --version, the
# help banner, and recorded in seqfetcher.lock.json).
SEQFETCHER_VERSION="1.3.0"

# =====================================
# General defaults
# =====================================

OUTDIR="downloads"
OUTPUT_FILE=""
TEMP_DIR="temp_downloads"
PARALLEL_JOBS=4
THREADS=4

# --- global behaviour flags (set by the pre-parse in seqfetcher.sh) ---
JSON_OUTPUT=false    # --json      : emit a machine-readable object on stdout
QUIET=false          # --quiet/-q  : silence [INFO]/[STEP]/[SUCCESS] on stderr
FORCE=false          # --force     : re-download even if the lockfile has it
REQUIRE_PINNED=false # --require-pinned : refuse sources that resolve "latest"

# =====================================
# Search
# =====================================

ORGANISM=""
INTERACTIVE=false
EXTRACT_GENES=false
# How many top-ranked results to display and write to the results table.
TOP_N=50
# assemblies (default) | pdb | alphafold
MODE="assemblies"

# --- structure search: search --pdb / search --alphafold ---
SEARCH_TEXT=""              # both: free-text query
SEARCH_METHOD=""            # pdb: x-ray | em | nmr
SEARCH_MAX_RESOLUTION=""    # pdb: max resolution in Angstrom
SEARCH_UNIPROT=""           # pdb: comma-separated UniProt accessions
SEARCH_LIGAND=""            # pdb: comma-separated chemical component ids
SEARCH_AFTER_DATE=""        # pdb: released on/after YYYY-MM-DD
SEARCH_BEFORE_DATE=""       # pdb: released on/before YYYY-MM-DD
SEARCH_MIN_CHAINS=""        # pdb: minimum protein polymer-entity count
SEARCH_SORT=""              # pdb: resolution | date | score
SEARCH_GENE=""              # alphafold: UniProt gene name
SEARCH_KEYWORD=""           # alphafold: UniProt keyword (KW-id or word)
SEARCH_PROTEOME=""          # alphafold: UniProt proteome id UPXXXXXXXXX
SEARCH_TAXON_ID=""          # alphafold: NCBI taxonomy id
SEARCH_REVIEWED=false       # alphafold: Swiss-Prot entries only
CHECK_ALPHAFOLD=false       # alphafold: verify each model + add pLDDT columns

# =====================================
# Assembly downloads
# =====================================

ACCESSION=""
ACCESSION_FILE=""

# =====================================
# Gene downloads
# =====================================

GENE_FILE=""
GENE_FILE_USER=false
GENE_ID=""
GENE_ID_USER=false

# =====================================
# Download dispatcher
# =====================================

DOWNLOAD_TYPE="assembly"

# =====================================
# SRA
# =====================================

SRA_METHOD=""

# =====================================
# GEO
# =====================================

GEO_ACCESSION=""

# =====================================
# Ensembl
# =====================================

ENSEMBL_FASTA=false
ENSEMBL_SPECIES=""
ENSEMBL_TYPE=""
ENSEMBL_RELEASE=""

# =====================================
# Transcriptome
# =====================================

TRANSCRIPTOME=false
TRANSCRIPTOME_ASSEMBLY=""
TRANSCRIPTOME_SPECIES=""
TRANSCRIPTOME_SOURCE="ncbi"
TRANSCRIPTOME_TYPE="cdna"

# =====================================
# Annotation-only downloads
# =====================================

ANNOTATION=false
ANNOTATION_FORMATS="gff3,gtf"   # subset of gff3,gtf,gbff

# =====================================
# Proteome
# =====================================

PROTEOME=false
PROTEOME_ASSEMBLY=""
PROTEOME_SPECIES=""
PROTEOME_SOURCE="ncbi"          # ncbi | ensembl | auto | uniprot
PROTEOME_TYPE="pep"
PROTEOME_ID=""                  # UniProt proteome id (with --source uniprot)

# =====================================
# Structure downloads (AlphaFold / RCSB PDB)
# =====================================

STRUCTURE=false
STRUCTURE_ALPHAFOLD=""          # comma-separated UniProt accessions
STRUCTURE_ALPHAFOLD_FILE=""
STRUCTURE_PDB=""                # comma-separated PDB ids
STRUCTURE_PDB_FILE=""
STRUCTURE_FORMAT="pdb"          # pdb | cif

# =====================================
# BioProject
# =====================================

BIOPROJECT_ACCESSION=""

# =====================================
# Ortholog downloads
# =====================================

ORTHOLOG=""
ORTHOLOG_USER=false
ORTHOLOG_FILE=""
ORTHOLOG_FILE_USER=false

# Optional. Raises the NCBI Entrez rate limit from 3 to 10 req/s.
# Register free at: https://www.ncbi.nlm.nih.gov/account/
NCBI_API_KEY="${NCBI_API_KEY:-}"