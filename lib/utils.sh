#!/usr/bin/env bash

# =============================================================================
# Utility Functions Module
# =============================================================================
# Core utilities for logging, argument parsing, and helper functions
# Used across all other modules

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BASEDIR="$(pwd)"
RENDERING_FOLDER_NAME="rendering"
# shellcheck disable=SC2034
TARGET_FOLDER="$BASEDIR/$RENDERING_FOLDER_NAME"

log_section() {
	echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

log_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1\n"
}

log_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Required:
  --project-name NAME       Project name (used for package naming)
  --organization NAME       Organization name

# Optional:
#  --registry-domain DOMAIN  Shadcn registry domain (interactive if not provided)
#  --azure-devops-url URL    Azure DevOps repository URL
#  --vercel-team-id ID       Vercel team ID for deployment linking
  --help                    Show this help message

Examples:
  $(basename "$0") --project-name my-ds --organization my-org

EOF
}

print_banner() {
	echo -e "${BLUE}"
	echo "╔═══════════════════════════════════════════════════════════════╗"
	echo "║           Design System Monorepo Setup Script.                ║"
	echo "║                                                               ║"
	echo "║  This script will bootstrap a complete Turbo monorepo with:   ║"
	echo "║  • Turborepo                                                  ║"
	echo "║  • Node.js LTS via nvm                                        ║"
	echo "║  • pnpm workspaces                                            ║"
	echo "║  • Shared configuration packages                              ║"
	echo "║  • UI component library                                       ║"
	echo "║  • Design token system                                        ║"
	echo "║  • Shadcn registry configuration                              ║"
	echo "╚═══════════════════════════════════════════════════════════════╝"
	echo -e "${NC}"
}

parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case $1 in
		--project-name)
			PROJECT_NAME="$2"
			shift 2
			;;
		--organization)
			ORGANIZATION_NAME="$2"
			shift 2
			;;
		# --registry-domain)
		# 	REGISTRY_DOMAIN="$2"
		# 	shift 2
		# 	;;
		# --azure-devops-url)
		# 	AZURE_DEVOPS_URL="$2"
		# 	shift 2
		# 	;;
		# --vercel-team-id)
		# 	VERCEL_TEAM_ID="$2"
		# 	shift 2
		# 	;;
		--help)
			show_usage
			exit 0
			;;
		*)
			log_error "Unknown option: $1"
			show_usage
			exit 1
			;;
		esac
	done

	if [[ -z "$PROJECT_NAME" ]]; then
		log_error "Project name is required. Use --project-name to specify."
		show_usage
		exit 1
	else
		# shellcheck disable=SC2034
		TARGET_FOLDER="$BASEDIR/$PROJECT_NAME"
	fi

	if [[ -z "$ORGANIZATION_NAME" ]]; then
		log_error "Organization name is required. Use --organization to specify."
		show_usage
		exit 1
	fi
}

get_author_name() {
	local username
	username=$(whoami)
	local IFS='.'
	read -ra name_parts <<<"$username"
	local author_name_temp=""
	for part in "${name_parts[@]}"; do
		author_name_temp+="${part^} "
	done
	# shellcheck disable=SC2034
	DEVELOPER="${author_name_temp::-1}, Unic AG"
}

# Get package dependencies from all packages or a specific package
# Usage:
#   get_package_deps "dependencies"              # Get all dependencies from all packages
#   get_package_deps "dependencies" "./pkg/path" # Get dependencies from specific package
#   get_package_deps "devDependencies"           # Get all devDependencies from all packages
get_package_deps() {
	local dep_type="${1:-dependencies}" # Default to 'dependencies' if no argument is provided
	local pkg_path="${2:-}"             # Optional: specific package.json path

	if [[ "$dep_type" != "dependencies" && "$dep_type" != "devDependencies" ]]; then
		log_error "Invalid dependency type: $dep_type. Must be 'dependencies' or 'devDependencies'."
		return 1
	fi

	# Define the jq filter once
	# shellcheck disable=SC2016
	local jq_filter='
		if .[$dep_type] then
			.[$dep_type] | to_entries[] | select(.value | startswith("workspace:") | not) | .key
		else
			empty
		end
	'

	# If a specific package path is provided, extract deps from that package only
	if [ -n "$pkg_path" ]; then
		jq -r --arg dep_type "$dep_type" "$jq_filter" "$pkg_path" 2>/dev/null | sort -u
	else
		# Otherwise, extract from all packages
		find . -name "package.json" -not -path "*/node_modules/*" -print0 | while IFS= read -r -d $'\0' pkg_file; do
			jq -r --arg dep_type "$dep_type" "$jq_filter" "$pkg_file"
		done | sort -u
	fi
}

# Helper function to update a package's dependencies to use catalog: protocol
# Usage: update_package_to_catalog "dependencies" "$pkg_path" "$pkg_dir" "$pkg_name"
# Uses jq for direct modification to avoid pnpm workspace resolution issues during setup
update_package_to_catalog() {
	local dep_type="$1"
	local pkg_path="$2"
	# shellcheck disable=SC2034
	local pkg_dir="$3"
	local pkg_name="$4"

	# Get dependencies for this package (excluding workspace: deps)
	local deps
	deps=$(get_package_deps "$dep_type" "$pkg_path")

	# Only proceed if we have dependencies
	if [ -n "$deps" ]; then
		log_info "  Updating $dep_type to catalog: in $pkg_name"

		# Use jq to update each dependency to use catalog: protocol
		echo "$deps" | while read -r dep_name; do
			if [ -n "$dep_name" ]; then
				log_info "    $dep_name -> catalog:"
				# Update the dependency version to "catalog:" using jq
				jq --arg dep "$dep_name" --arg type "$dep_type" '
					if .[$type][$dep] then .[$type][$dep] = "catalog:" else . end
				' "$pkg_path" >"$pkg_path.tmp" && mv "$pkg_path.tmp" "$pkg_path"
			fi
		done
	fi
}

# Resolve the latest version of a package from npm registry
get_latest_version() {
	local package_name="$1"
	local min_age_minutes=1440
	local cutoff_time
	cutoff_time=$(date -v-${min_age_minutes}M +%s 2>/dev/null || date -d "${min_age_minutes} minutes ago" +%s 2>/dev/null)

	if [ -z "$cutoff_time" ]; then
		# Fallback: can't determine age, just use latest
		npm view "$package_name" version 2>/dev/null || echo ""
		return
	fi

	local time_data
	time_data=$(npm view "$package_name" time --json 2>/dev/null)

	if [ -z "$time_data" ]; then
		npm view "$package_name" version 2>/dev/null || echo ""
		return
	fi

	# Find the latest version published before the cutoff time
	local mature_version
	mature_version=$(echo "$time_data" | jq -r \
		--argjson cutoff "$cutoff_time" \
		'to_entries
		| map(select(.key != "created" and .key != "modified"))
		| map(select((.value | fromdateiso8601) <= $cutoff))
		| sort_by(.value)
		| last
		| .key // empty' 2>/dev/null)

	if [ -n "$mature_version" ]; then
		echo "$mature_version"
	else
		# All versions are too new — fall back to latest and let pnpm decide
		npm view "$package_name" version 2>/dev/null || echo ""
	fi
}

# Add a package to the catalog in pnpm-workspace.yaml
add_to_catalog() {
	local package_name="$1"
	local version="$2"

	# Check if catalog section exists, if not create it
	if ! yq e '.catalog' pnpm-workspace.yaml | grep -q -v "null"; then
		yq e -i '.catalog = {}' pnpm-workspace.yaml
	fi

	# Add the package to catalog with exact version
	yq e -i ".catalog.\"$package_name\" = \"$version\"" pnpm-workspace.yaml
}
