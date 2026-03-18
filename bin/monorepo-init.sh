#!/usr/bin/env bash

# =============================================================================
# Monorepo Initialization Script (Refactored)
# =============================================================================
# This is the main orchestrator that sources modular library files
# and executes the monorepo setup workflow.
#
# Usage:
#   ./bin/monorepo-init.sh --project-name my-project --organization my-org
#
# For more information, see README.md

set -euo pipefail

# =============================================================================
# Script Setup
# =============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

BASEDIR="$(pwd)"
RENDERING_FOLDER_NAME="rendering"
TARGET_FOLDER="$BASEDIR/$RENDERING_FOLDER_NAME"

# Source all library modules
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/prerequisites.sh"
source "$LIB_DIR/repository.sh"
source "$LIB_DIR/configuration.sh"
source "$LIB_DIR/package-prettier.sh"
source "$LIB_DIR/package-design-tokens.sh"
source "$LIB_DIR/package-storybook.sh"
source "$LIB_DIR/dependencies.sh"
source "$LIB_DIR/finalization.sh"

# =============================================================================
# Main Execution Flow
# =============================================================================

main() {
	# Display banner
	print_banner

	# Parse command-line arguments
	parse_arguments "$@"
	get_author_name

	# Check and install prerequisites
	log_section "Prerequisites"
	check_pnpm
	check_yq
	check_jq
	prepare_node
	log_success "All prerequisites are met."

	# Initialize repository
	log_section "Repository Initialization"
	init_repo
	rename_ui_package
	setup_workspace
	setup_npmrc
	log_success "Repository initialized successfully."

	# Create root-level configuration files
	log_section "Root Configuration"
	create_license
	create_editorconfig
	create_eslint_config
	create_prettier_config
	create_prettier_ignore
	log_success "Root configuration files created."

	# Prettier config package
	log_section "Package: @repo/prettier-config"
	create_prettier_config_package
	add_prettier_base_config
	add_prettier_config_readme
	log_success "Prettier config package setup complete."

	# Design tokens package
	log_section "Package: @repo/design-tokens"
	create_design_tokens_package
	add_design_tokens_config
	add_design_tokens_sample
	add_design_tokens_tsconfig
	add_design_tokens_readme
	log_success "Design tokens package setup complete."

	# Storybook React app
	log_section "App: Storybook React"
	# CLI creates main.ts with addon configuration that we preserve
	init_storybook_with_cli
	# CLI succeeded - use it to add addons (auto-configures main.ts)
	# IMPORTANT: Run this BEFORE customizing preview.ts, so CLI can parse the simple generated files
	# install_storybook_addons_via_cli
	finalize_storybook_package_json

	# Patch CLI-generated files with monorepo-specific config
	# (Run AFTER addon CLI commands to avoid parsing issues)
	customize_storybook_preview_ts
	add_storybook_vitest_setup

	add_storybook_vitest_config
	add_storybook_styles
	add_storybook_sample_stories
	add_storybook_tsconfig
	add_storybook_eslint_config
	add_storybook_msw_handlers
	add_storybook_readme

	log_success "Storybook React app setup complete"

	# Manage dependencies
	log_section "Dependency Management"
	define_catalog
	standardize_packages

	# Finalization
	log_section "Finalization"
	create_vercel_json
	copy_helper_scripts
	setup_vscode
	document_dependency_management
	install_dependencies

	# Print summary
	print_summary
}

# Run main function
main "$@"
