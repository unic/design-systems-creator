# shellcheck shell=bash
define_catalog() {
	log_info "Defining pnpm workspace catalog..."
	cd "$TARGET_FOLDER" || exit

	local tmp_file
	tmp_file=$(mktemp)
	trap 'rm -f "$tmp_file"' RETURN

	# Step 1: Collect all unique dependencies from ALL packages (including root, excluding workspace: refs)
	log_info "Step 1: Collecting all dependencies from all packages..."

	find . -name "package.json" -not -path "*/node_modules/*" | while read -r pkg_file; do
		jq -r '(.dependencies // {}) + (.devDependencies // {}) | to_entries[] | select(.value | startswith("workspace:") | not) | .key' "$pkg_file" 2>/dev/null
	done | sort -u | grep -v '^$' >"$tmp_file"

	# Step 2: Resolve latest versions and add to catalog
	log_info "Step 2: Resolving latest versions and populating catalog..."

	while read -r package_name; do
		if [ -n "$package_name" ]; then
			log_info "  Resolving $package_name..."
			local version
			version=$(get_latest_version "$package_name")
			if [ -n "$version" ]; then
				add_to_catalog "$package_name" "$version"
				log_info "    Added $package_name@$version to catalog"
			else
				log_warning "    Could not resolve version for $package_name"
			fi
		fi
	done <"$tmp_file"

	rm -f "$tmp_file"

	# Step 3: Update workspace packages to use catalog: protocol
	log_info "Step 3: Updating workspace packages to use catalog: protocol..."

	find . -name "package.json" -not -path "*/node_modules/*" | while read -r pkg_path; do
		local pkg_dir
		pkg_dir=$(dirname "$pkg_path")

		# Skip root package (root keeps exact versions, workspace packages use catalog:)
		if [ "$pkg_dir" = "." ]; then
			continue
		fi

		local pkg_name
		pkg_name=$(cd "$pkg_dir" && pnpm pkg get name | tr -d '"')
		[ -z "$pkg_name" ] && pkg_name="unknown"

		log_info "Updating package: $pkg_name"

		# Update both dependencies and devDependencies using helper
		update_package_to_catalog "dependencies" "$pkg_path" "$pkg_dir" "$pkg_name"
		update_package_to_catalog "devDependencies" "$pkg_path" "$pkg_dir" "$pkg_name"
	done

	# Step 4: Update root devDependencies to use catalog: protocol
	log_info "Step 4: Updating root package.json to use catalog: protocol..."

	local root_dev_deps
	root_dev_deps=$(jq -r '.devDependencies // {} | to_entries[] | select(.value | startswith("workspace:") | not) | .key' package.json 2>/dev/null || echo "")

	if [ -n "$root_dev_deps" ]; then
		echo "$root_dev_deps" | while read -r dep_name; do
			if [ -n "$dep_name" ]; then
				log_info "  $dep_name -> catalog:"
				jq --arg dep "$dep_name" '
					.devDependencies[$dep] = "catalog:"
				' package.json >package.json.tmp && mv package.json.tmp package.json
			fi
		done
	fi

	log_success "pnpm workspace catalog defined and packages updated."
}

standardize_packages() {
	log_info "Standardizing package.json files across workspace..."
	cd "$TARGET_FOLDER" || exit

	local package_manager
	package_manager="pnpm@$(pnpm -v)"

	if [ -z "$package_manager" ]; then
		log_warning "No packageManager field found in root package.json"
	else
		log_info "Syncing packageManager: $package_manager"
	fi

	# Define standard values
	local version="1.0.0"
	local license="LGPL-3.0-or-later"
	local author="${DEVELOPER}"

	# Find all package.json files (including root, excluding node_modules)
	find . -name "package.json" -not -path "*/node_modules/*" | while read -r pkg_path; do
		local pkg_dir
		pkg_dir=$(dirname "$pkg_path")
		local pkg_name
		pkg_name=$(cd "$pkg_dir" && pnpm pkg get name | tr -d '"')
		[ -z "$pkg_name" ] && pkg_name="unknown"

		# Check if this is the root package
		if [ "$pkg_dir" = "." ]; then
			log_info "Standardizing root package..."
			# Root package: set all fields including name and description
			pnpm pkg set private=true --json
			pnpm pkg set \
				"name=@$(echo "${ORGANIZATION_NAME}" | tr '[:upper:]' '[:lower:]')/${PROJECT_NAME}" \
				"description=${ORGANIZATION_NAME} monorepo for Website and Design System" \
				"version=$version" \
				"author=$author" \
				"license=$license" \
				"packageManager=$package_manager"
		else
			log_info "Standardizing $pkg_name..."
			# Workspace packages: preserve name and description, update other fields
			(cd "$pkg_dir" && pnpm pkg set private=true --json)
			(cd "$pkg_dir" && pnpm pkg set \
				"version=$version" \
				"author=$author" \
				"license=$license" \
				"packageManager=$package_manager")
		fi
	done

	log_success "All packages standardized."
}
