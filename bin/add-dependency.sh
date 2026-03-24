#!/usr/bin/env bash

# Add Dependency Helper Script
# This script helps developers add dependencies following the monorepo's best practices:
# - All versions are defined in the catalog (pnpm-workspace.yaml)
# - Packages reference versions using catalog: protocol
# - All installations use exact versions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
PACKAGE_NAME=""
TARGET_PATH=""
DEP_TYPE="dep" # dep, dev, peer
WORKSPACE_ROOT=""

log_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

log_prompt() {
	echo -e "${CYAN}[?]${NC} $1"
}

show_usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Add a dependency to a package following monorepo best practices.
If no arguments are provided, interactive mode will be used.

Options:
  --package, -p NAME     Package name to add (e.g., react, lodash)
  --to, -t PATH          Target package path (e.g., packages/ui-react, apps/website)
  --type TYPE            Dependency type: dep, dev, or peer (default: dep)
  --dev, -D              Shorthand for --type dev
  --peer, -P             Shorthand for --type peer
  --help, -h             Show this help message

Examples:
  $(basename "$0")                                           # Interactive mode
  $(basename "$0") --package react --to packages/ui-react --type peer
  $(basename "$0") -p typescript -t packages/tokens -D
  $(basename "$0") --package clsx --to apps/website

Dependency Types:
  dep   - Regular dependency (dependencies)
  dev   - Development dependency (devDependencies)
  peer  - Peer dependency (peerDependencies)

EOF
	exit 0
}

# Find workspace root by looking for pnpm-workspace.yaml
find_workspace_root() {
	local current_dir="$PWD"
	while [[ "$current_dir" != "/" ]]; do
		if [[ -f "$current_dir/pnpm-workspace.yaml" ]]; then
			WORKSPACE_ROOT="$current_dir"
			return 0
		fi
		current_dir="$(dirname "$current_dir")"
	done
	log_error "Could not find workspace root (no pnpm-workspace.yaml found)"
	exit 1
}

check_yq() {
	log_info "Checking for yq installation..."

	if ! command -v yq &>/dev/null; then
		log_warning "yq not found"

		if command -v brew &>/dev/null; then
			log_info "Installing yq via Homebrew..."
			brew install yq
		elif command -v pnpm &>/dev/null; then
			log_info "Installing yq globally via pnpm..."
			pnpm add -g yq
		else
			log_error "Could not install yq. Please install it manually: https://github.com/mikefarah/yq"
			exit 1
		fi
	fi

	log_success "yq $(yq --version | head -1) ready."
}

check_jq() {
	log_info "Checking for jq installation..."

	if ! command -v jq &>/dev/null; then
		log_warning "jq not found"

		if command -v brew &>/dev/null; then
			log_info "Installing jq via Homebrew..."
			brew install jq
		else
			log_error "Could not install jq. Please install it manually: https://github.com/jqlang/jq"
			exit 1
		fi
	fi

	log_success "jq $(jq --version) ready."
}

# Get list of available packages/apps in the workspace
get_available_targets() {
	find "$WORKSPACE_ROOT" -name "package.json" -not -path "*/node_modules/*" | while read -r pkg_file; do
		local pkg_dir
		pkg_dir=$(dirname "$pkg_file")
		local rel_path="${pkg_dir#"$WORKSPACE_ROOT"/}"
		# Skip root package
		if [[ "$rel_path" != "." && "$rel_path" != "" ]]; then
			echo "$rel_path"
		fi
	done | sort
}

# Check if package exists in catalog
package_in_catalog() {
	local pkg_name="$1"
	local catalog_version
	catalog_version=$(yq e ".catalog.\"$pkg_name\" // \"\"" "$WORKSPACE_ROOT/pnpm-workspace.yaml" 2>/dev/null)
	[[ -n "$catalog_version" ]]
}

# Get package version from catalog
get_catalog_version() {
	local pkg_name="$1"
	yq e ".catalog.\"$pkg_name\" // \"\"" "$WORKSPACE_ROOT/pnpm-workspace.yaml" 2>/dev/null
}

# Get latest version from npm registry
get_latest_version() {
	local pkg_name="$1"
	npm view "$pkg_name" version 2>/dev/null || echo ""
}

# Add package to catalog
add_to_catalog() {
	local pkg_name="$1"
	local version="$2"

	# Check if catalog section exists, if not create it
	if ! yq e '.catalog' "$WORKSPACE_ROOT/pnpm-workspace.yaml" | grep -q -v "null"; then
		yq e -i '.catalog = {}' "$WORKSPACE_ROOT/pnpm-workspace.yaml"
	fi

	# Add the package to catalog with exact version
	yq e -i ".catalog.\"$pkg_name\" = \"$version\"" "$WORKSPACE_ROOT/pnpm-workspace.yaml"
	log_success "Added $pkg_name@$version to catalog"
}

# Add dependency to target package
add_to_package() {
	local pkg_name="$1"
	local target="$2"
	local type="$3"

	local target_dir="$WORKSPACE_ROOT/$target"

	if [[ ! -d "$target_dir" ]]; then
		log_error "Target directory does not exist: $target"
		exit 1
	fi

	if [[ ! -f "$target_dir/package.json" ]]; then
		log_error "No package.json found in: $target"
		exit 1
	fi

	# Determine pnpm flags based on dependency type
	local pnpm_flags="--save-exact"
	case "$type" in
	dev)
		pnpm_flags+=" -D"
		;;
	peer)
		pnpm_flags+=" --save-peer"
		;;
	dep)
		pnpm_flags+=" -P"
		;;
	esac

	log_info "Adding $pkg_name to $target as $type dependency..."

	(cd "$target_dir" && pnpm add "$pnpm_flags" "${pkg_name}@catalog:")

	log_success "Added $pkg_name to $target"
}

# Interactive: select target package
interactive_select_target() {
	log_prompt "Select target package:"
	echo ""

	local targets=()
	while IFS= read -r target; do
		targets+=("$target")
	done < <(get_available_targets)

	if [[ ${#targets[@]} -eq 0 ]]; then
		log_error "No packages found in workspace"
		exit 1
	fi

	local i=1
	for target in "${targets[@]}"; do
		echo "  $i) $target"
		((i++))
	done
	echo ""

	local selection
	read -rp "Enter number or path: " selection

	# Check if selection is a number
	if [[ "$selection" =~ ^[0-9]+$ ]]; then
		local index=$((selection - 1))
		if [[ $index -ge 0 && $index -lt ${#targets[@]} ]]; then
			TARGET_PATH="${targets[$index]}"
		else
			log_error "Invalid selection"
			exit 1
		fi
	else
		# Assume it's a path
		TARGET_PATH="$selection"
	fi
}

# Interactive: select dependency type
interactive_select_type() {
	log_prompt "Select dependency type:"
	echo ""
	echo "  1) dep  - Regular dependency (dependencies)"
	echo "  2) dev  - Development dependency (devDependencies)"
	echo "  3) peer - Peer dependency (peerDependencies)"
	echo ""

	local selection
	read -rp "Enter number or type [dep]: " selection

	case "$selection" in
	1 | dep | "")
		DEP_TYPE="dep"
		;;
	2 | dev)
		DEP_TYPE="dev"
		;;
	3 | peer)
		DEP_TYPE="peer"
		;;
	*)
		log_error "Invalid selection"
		exit 1
		;;
	esac
}

# Interactive: enter package name
interactive_enter_package() {
	log_prompt "Enter package name to add:"
	read -rp "> " PACKAGE_NAME

	if [[ -z "$PACKAGE_NAME" ]]; then
		log_error "Package name cannot be empty"
		exit 1
	fi
}

# Handle package not in catalog
handle_missing_from_catalog() {
	local pkg_name="$1"

	log_warning "$pkg_name is not in the catalog"

	local latest_version
	latest_version=$(get_latest_version "$pkg_name")

	if [[ -z "$latest_version" ]]; then
		log_error "Could not find $pkg_name in npm registry"
		exit 1
	fi

	log_prompt "Would you like to add $pkg_name@$latest_version to the catalog? [Y/n]"
	local confirm
	read -rp "> " confirm

	case "$confirm" in
	"" | y | Y | yes | Yes | YES)
		add_to_catalog "$pkg_name" "$latest_version"
		;;
	*)
		log_info "Aborted. Please add $pkg_name to the catalog manually:"
		echo ""
		echo "  In pnpm-workspace.yaml:"
		echo "  catalog:"
		echo "    $pkg_name: $latest_version"
		echo ""
		exit 1
		;;
	esac
}

parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case $1 in
		--package | -p)
			PACKAGE_NAME="$2"
			shift 2
			;;
		--to | -t)
			TARGET_PATH="$2"
			shift 2
			;;
		--type)
			DEP_TYPE="$2"
			shift 2
			;;
		--dev | -D)
			DEP_TYPE="dev"
			shift
			;;
		--peer | -P)
			DEP_TYPE="peer"
			shift
			;;
		--help | -h)
			show_usage
			;;
		*)
			log_error "Unknown option: $1"
			show_usage
			;;
		esac
	done
}

main() {
	find_workspace_root
	check_yq
	check_jq

	parse_arguments "$@"

	# Interactive mode if arguments are missing
	if [[ -z "$PACKAGE_NAME" ]]; then
		echo ""
		echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
		echo -e "${BLUE}║              Add Dependency Helper                            ║${NC}"
		echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
		echo ""

		interactive_enter_package
	fi

	if [[ -z "$TARGET_PATH" ]]; then
		interactive_select_target
	fi

	if [[ "$DEP_TYPE" == "dep" && -z "${1:-}" ]]; then
		# Only prompt for type in interactive mode
		interactive_select_type
	fi

	# Validate dependency type
	case "$DEP_TYPE" in
	dep | dev | peer) ;;
	*)
		log_error "Invalid dependency type: $DEP_TYPE (must be dep, dev, or peer)"
		exit 1
		;;
	esac

	echo ""
	log_info "Summary:"
	echo "  Package: $PACKAGE_NAME"
	echo "  Target:  $TARGET_PATH"
	echo "  Type:    $DEP_TYPE"
	echo ""

	# Check if package is in catalog
	if ! package_in_catalog "$PACKAGE_NAME"; then
		handle_missing_from_catalog "$PACKAGE_NAME"
	else
		local version
		version=$(get_catalog_version "$PACKAGE_NAME")
		log_info "$PACKAGE_NAME@$version found in catalog"
	fi

	# Add to package
	add_to_package "$PACKAGE_NAME" "$TARGET_PATH" "$DEP_TYPE"

	echo ""
	log_success "Done!"
}

# Run main function with all arguments if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
