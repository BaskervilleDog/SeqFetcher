#!/usr/bin/env bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC}  $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC}  $*"
}

log_step() {
    echo
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}[STEP]${NC} $*"
    echo -e "${CYAN}==================================================${NC}"
    echo
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}