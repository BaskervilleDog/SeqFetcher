#!/usr/bin/env bash

# ============================================================
# Version and Variable Definition
# ============================================================

VERSION="1.2.0"

# Default values
THREADS=8
OUTPUT_DIR="downloads"
TEMP_DIR="temp_downloads"
DRY_RUN=false
VERBOSE=false
MAX_SIZE="200G"
MAX_RETRIES=3
ENSEMBL_BASE="https://ftp.ensembl.org/pub/current_fasta"
LOG_FILE=""

# Global state
COMMAND=""
SUBCOMMAND=""
GLOBAL_ARGS=()
ENSEMBL_TYPE=""
ENSEMBL_RELEASE=""
