#!/usr/bin/env bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation settings
INSTALL_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/seqfetcher"
SCRIPT_NAME="seqfetcher"

# Helper functions
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if running from correct directory
check_source_files() {
    if [[ ! -f "seqfetcher.sh" ]]; then
        print_error "seqfetcher.sh not found in current directory"
        echo "Please run this script from the SeqFetcher repository root"
        exit 1
    fi
    
    if [[ ! -d "lib" ]]; then
        print_error "lib/ directory not found"
        echo "Please run this script from the SeqFetcher repository root"
        exit 1
    fi
}

# Check for required dependencies
check_dependencies() {
    local missing_deps=()
    
    print_info "Checking dependencies..."
    
    # Required tools
    if ! command -v datasets &> /dev/null; then
        missing_deps+=("NCBI Datasets CLI")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v parallel &> /dev/null; then
        missing_deps+=("GNU Parallel")
    fi
    
    # Optional tools (warnings only)
    if ! command -v fasterq-dump &> /dev/null && ! command -v prefetch &> /dev/null; then
        print_warning "SRA Toolkit not found (optional - needed for SRA downloads)"
    fi
    
    # Report missing required dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "Installation instructions:"
        echo "  NCBI Datasets: https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/"
        echo "  jq:            brew install jq  OR  apt-get install jq"
        echo "  GNU Parallel:  brew install parallel  OR  apt-get install parallel"
        exit 1
    else
        print_success "All required dependencies found"
    fi
}

# Install SeqFetcher
install_seqfetcher() {
    local APP_DIR="${HOME}/.local/share/seqfetcher"

    print_info "Installing SeqFetcher..."

    mkdir -p "$APP_DIR"
    mkdir -p "$INSTALL_DIR"

    # Clean previous installation
    rm -rf "$APP_DIR"

    # Copy application
    mkdir -p "$APP_DIR"
    cp seqfetcher.sh "$APP_DIR/"
    cp -r lib "$APP_DIR/"

    chmod +x "$APP_DIR/seqfetcher.sh"

    print_success "Application files installed"

    # Create launcher
    cat > "${INSTALL_DIR}/${SCRIPT_NAME}" <<EOF
#!/usr/bin/env bash
exec "${APP_DIR}/seqfetcher.sh" "\$@"
EOF

    chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"

    print_success "Launcher installed"
}

# Check if directory is in PATH
check_path() {
    if [[ ":$PATH:" == *":${INSTALL_DIR}:"* ]]; then
        print_success "${INSTALL_DIR} is already in PATH"
        return 0
    else
        print_warning "${INSTALL_DIR} is not in PATH"
        return 1
    fi
}

# Provide instructions for adding to PATH
show_path_instructions() {
    echo ""
    echo "────────────────────────────────────────────────────────────"
    echo "To add SeqFetcher to your PATH, add this line to your shell config:"
    echo ""
    
    # Detect shell
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo "  echo 'export PATH=\"\$PATH:${INSTALL_DIR}\"' >> ~/.zshrc"
        echo "  source ~/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        echo "  echo 'export PATH=\"\$PATH:${INSTALL_DIR}\"' >> ~/.bashrc"
        echo "  source ~/.bashrc"
    else
        echo "  export PATH=\"\$PATH:${INSTALL_DIR}\""
    fi
    
    echo ""
    echo "Or run for current session only:"
    echo "  export PATH=\"\$PATH:${INSTALL_DIR}\""
    echo "────────────────────────────────────────────────────────────"
}

# Verify installation
verify_installation() {
    local APP_DIR="${HOME}/.local/share/seqfetcher"

    print_info "Verifying installation..."

    [[ -x "${INSTALL_DIR}/${SCRIPT_NAME}" ]] \
        || { print_error "Launcher missing"; exit 1; }

    [[ -f "${APP_DIR}/seqfetcher.sh" ]] \
        || { print_error "Main script missing"; exit 1; }

    [[ -d "${APP_DIR}/lib" ]] \
        || { print_error "Library directory missing"; exit 1; }

    if "${INSTALL_DIR}/${SCRIPT_NAME}" --help >/dev/null 2>&1; then
        print_success "Installation verified"
    else
        print_error "Runtime verification failed"
        exit 1
    fi
}

uninstall_seqfetcher() {
    print_info "Removing SeqFetcher..."

    rm -f "${INSTALL_DIR}/${SCRIPT_NAME}"
    rm -rf "${APP_DIR}"

    print_success "SeqFetcher uninstalled"
}

# Main installation
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           SeqFetcher Installation Script                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Run checks and installation
    check_source_files
    check_dependencies
    install_seqfetcher
    verify_installation
    
    # Installation complete
    echo ""
    print_success "Installation complete!"
    echo ""
    print_info "Installed to: ${INSTALL_DIR}/${SCRIPT_NAME}"
    print_info "Library files: ${LIB_DIR}"
    
    # Check PATH and provide instructions if needed
    if ! check_path; then
        show_path_instructions
    fi
    
    echo ""
    print_info "Test your installation:"
    echo "  ${SCRIPT_NAME} --help"
    echo ""
    print_info "Quick start examples:"
    echo "  ${SCRIPT_NAME} search --organism \"Escherichia coli\""
    echo "  ${SCRIPT_NAME} download --accession GCF_000005845.2"
    echo "  ${SCRIPT_NAME} download --geo GSE280953"
    echo ""
}

# Run main installation
main