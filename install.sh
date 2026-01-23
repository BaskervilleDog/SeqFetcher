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
SCRIPT_NAME="seqfetcher"
LIB_DIR="${INSTALL_DIR}/seqfetcher_lib"

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
    print_info "Installing SeqFetcher to: ${INSTALL_DIR}"
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    
    # Copy main script
    cp seqfetcher.sh "${INSTALL_DIR}/${SCRIPT_NAME}"
    chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"
    print_success "Installed main script"
    
    # Copy library files
    mkdir -p "$LIB_DIR"
    cp -r lib/* "$LIB_DIR/"
    print_success "Installed library files"
    
    # Update BASE_DIR and lib paths in installed script
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS (BSD sed)
        sed -i '' "s|BASE_DIR=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)\"|BASE_DIR=\"${INSTALL_DIR}\"|g" "${INSTALL_DIR}/${SCRIPT_NAME}"
        sed -i '' "s|\$BASE_DIR/lib/|\$BASE_DIR/seqfetcher_lib/|g" "${INSTALL_DIR}/${SCRIPT_NAME}"
    else
        # Linux (GNU sed)
        sed -i "s|BASE_DIR=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)\"|BASE_DIR=\"${INSTALL_DIR}\"|g" "${INSTALL_DIR}/${SCRIPT_NAME}"
        sed -i "s|\$BASE_DIR/lib/|\$BASE_DIR/seqfetcher_lib/|g" "${INSTALL_DIR}/${SCRIPT_NAME}"
    fi
    print_success "Updated script paths"
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
    print_info "Verifying installation..."
    
    if [[ -x "${INSTALL_DIR}/${SCRIPT_NAME}" ]]; then
        print_success "SeqFetcher executable found"
    else
        print_error "Installation verification failed"
        exit 1
    fi
    
    if [[ -d "$LIB_DIR" ]]; then
        print_success "Library files found"
    else
        print_error "Library files missing"
        exit 1
    fi
    
    # Try to run help
    if "${INSTALL_DIR}/${SCRIPT_NAME}" --help &> /dev/null; then
        print_success "SeqFetcher can execute successfully"
    else
        print_warning "SeqFetcher may have runtime issues"
    fi
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