#!/usr/bin/env bash

# =============================================================================
# Repository Module
# =============================================================================
# Functions for initializing the Turbo monorepo and configuring workspace

# Setup Turbo monorepo with pnpm
init_repo() {
	log_info "Creating a new Turbo monorepo in ${TARGET_FOLDER}..."
	cd "$BASEDIR" || exit

	pnpm dlx create-turbo@latest "$TARGET_FOLDER" -m pnpm --skip-install -e "with-tailwind"

	cd "$TARGET_FOLDER" || exit
	rm -rf apps/docs

	# Update packageManager and engines in root package.json
	log_info "Setting packageManager to pnpm@$PNPM_VERSION in root package.json..."
	pnpm pkg set "packageManager=pnpm@$PNPM_VERSION" "engines.node=>=$(node --version)"

	log_success "Turbo monorepo ready."
}

# Rename @repo/ui to @repo/ui-react for framework-specific naming convention
rename_ui_package() {
	log_info "Renaming @repo/ui to @repo/ui-react..."
	cd "$TARGET_FOLDER" || exit

	# Step 1: Rename the directory
	if [ -d "packages/ui" ]; then
		mv packages/ui packages/ui-react
		log_info "  Renamed packages/ui -> packages/ui-react"
	else
		log_warning "  packages/ui directory not found, skipping rename"
		return 0
	fi

	# Step 2: Update package name in ui-react/package.json
	if [ -f "packages/ui-react/package.json" ]; then
		jq '.name = "@repo/ui-react"' packages/ui-react/package.json >packages/ui-react/package.json.tmp &&
			mv packages/ui-react/package.json.tmp packages/ui-react/package.json
		log_info "  Updated package name to @repo/ui-react"
	fi

	# Step 3: Update dependencies in apps/web/package.json
	if [ -f "apps/web/package.json" ]; then
		# Check if @repo/ui exists in dependencies and replace with @repo/ui-react
		if jq -e '.dependencies["@repo/ui"]' apps/web/package.json >/dev/null 2>&1; then
			jq '.dependencies["@repo/ui-react"] = .dependencies["@repo/ui"] | del(.dependencies["@repo/ui"])' \
				apps/web/package.json >apps/web/package.json.tmp &&
				mv apps/web/package.json.tmp apps/web/package.json
			log_info "  Updated apps/web/package.json dependency: @repo/ui -> @repo/ui-react"
		fi
	fi

	# Step 4: Update turbo.json if it references @repo/ui
	if [ -f "turbo.json" ]; then
		if grep -q '@repo/ui' turbo.json; then
			sed -i '' 's/@repo\/ui/@repo\/ui-react/g' turbo.json
			log_info "  Updated turbo.json references: @repo/ui -> @repo/ui-react"
		fi
	fi

	log_success "@repo/ui renamed to @repo/ui-react"
}

setup_workspace() {
	log_info "Appending workspace setup..."
	cd "$TARGET_FOLDER" || exit

	cat >>pnpm-workspace.yaml <<'EOF'

# =======================================================
# Control 1: Lifecycle Script Management
# Ensures we're making deliberate choices upfront rather than potentially discovering issues later

# Pre and Post install scripts are blocked by pnpm and installation continues with warnings.
# These would be too easy to ignore, especially since installation appears to succeed. We want stricter control.
# Force installation to fails immediately when it encounters lifecycle scripts
strictDepBuilds: true

# 1. Identify which packages have lifecycle scripts —pnpm tells you exactly which ones—.
# 2. Research what each script does, (feed the self-contained preinstall or postinstall script into a generative AI for interpretation)
# 3. Use human judgment to make a conscious, documented decision about whether to allow or block it

onlyBuiltDependencies:
- "@parcel/watcher"
- "esbuild"
- "sharp"
# "necessary" == packages that genuinely need their lifecycle scripts to function
# Ex: native extensions that compile from source or database drivers that link against platform-specific libraries

ignoredBuiltDependencies:
# - package-with-unnecessary-build-scripts
# "unnecessary" == scripts for optional optimizations or setup steps that don't affect whether the package functions in our use case
# =======================================================

# =======================================================
# Control 2: Release Cooldown
# Block installation of package versions published within a cooldown period
# Give the community time to detect and remove malicious packages before they reach your environment.
# 1440 minutes = 24h = 1 day
minimumReleaseAge: 0

# Shai-hulud 1: detected in 2.5 hours
# Shai-hulud 2: detected in 12 hours
# We're not always on the absolute latest versions of packages—despite best efforts.
# So this cooldown policy aligns more with our reality than it disrupts it.

minimumReleaseAgeExclude:
# - next
# - "@next/env"
# - turbo
# =======================================================

# =======================================================
# Control 3: Trust Policy
# Blocks installation when a package version has weaker authentication than previously published versions,
# often a sign that an attacker compromised maintainer's credentials and published from their own machine instead of the official CI/CD pipeline.
trustPolicy: no-downgrade

# In general, the dependencies excluded here lack provenance at the given versions but had provenance at earlier versions
# We have to go case by case when an error is provided like:
# ERR_PNPM_TRUST_DOWNGRADE High-risk trust downgrade for "semver@6.3.1" (possible package takeover)

trustPolicyExclude:
# https://github.com/pnpm/pnpm/issues/10202
- semver@6.3.1
# https://github.com/nodejs/undici/issues/4666
- "undici-types@6.21.0"
# =======================================================

preferWorkspacePackages: true

engineStrict: true

catalogMode: "prefer"

EOF

	echo "useNodeVersion: $(node -v | sed 's/v//')" >>pnpm-workspace.yaml

	log_success "pnpm-workspace updated"
}

setup_npmrc() {
	log_info "Creating .npmrc configuration..."
	cd "$TARGET_FOLDER" || exit

	cat >.npmrc <<'EOF'
auto-install-peers = true
save-exact = true
save-prefix = ""
EOF

	log_success ".npmrc created"
}
