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
	pnpm pkg set "packageManager=pnpm@$PNPM_VERSION" "engines.node=>=$(node --version | sed 's/^v//')"

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

	# Step 4: Update turbo.json — rename @repo/ui and add dependsOn to dev task
	if [ -f "turbo.json" ]; then
		if grep -q '@repo/ui' turbo.json; then
			tmp_sed_file="$(mktemp)"
			sed 's/@repo\/ui/@repo\/ui-react/g' turbo.json >"$tmp_sed_file" && mv "$tmp_sed_file" turbo.json
			log_info "  Updated turbo.json references: @repo/ui -> @repo/ui-react"
		fi
		# Make dev task depend on upstream builds so packages are built before dev servers start
		jq '.tasks.dev = (.tasks.dev // {})
			| .tasks.dev.dependsOn =
				(
					(.tasks.dev.dependsOn // [])
					| (if (type == "array") then . else [.] end)
					| if index("^build") then . else . + ["^build"] end
				)
		' turbo.json >turbo.json.tmp && mv turbo.json.tmp turbo.json
		log_info "  Added dependsOn to turbo.json dev task"
	fi

	# Step 5: Update @repo/ui imports in app source files
	find apps -type f \( -name "*.tsx" -o -name "*.ts" -o -name "*.css" \) | while read -r src_file; do
		if grep -q '@repo/ui' "$src_file"; then
			local tmp_src
			tmp_src="$(mktemp)"
			sed 's|@repo/ui/|@repo/ui-react/|g; s|@repo/ui"|@repo/ui-react"|g' "$src_file" >"$tmp_src" && mv "$tmp_src" "$src_file"
			log_info "  Updated @repo/ui imports in $src_file"
		fi
	done

	# Step 6: Add rootDir to ui-react/tsconfig.json (required by TypeScript 6+)
	if [ -f "packages/ui-react/tsconfig.json" ]; then
		jq '.compilerOptions.rootDir = "src"' packages/ui-react/tsconfig.json >packages/ui-react/tsconfig.json.tmp &&
			mv packages/ui-react/tsconfig.json.tmp packages/ui-react/tsconfig.json
		log_info "  Added rootDir to packages/ui-react/tsconfig.json"
	fi

	# Step 7: Add "." root export and "./styles.css" subpath to ui-react/package.json and create index.ts
	if [ -f "packages/ui-react/package.json" ]; then
		jq '.exports = ({"./styles.css": "./dist/index.css", ".": "./dist/index.js"} + .exports) | .type = "module" | .scripts["build:components"] = (.scripts.build // "tsc --build") | .scripts["build:styles"] = "tailwindcss -i ./src/styles.css -o ./dist/index.css" | .scripts.build = "pnpm build:styles && pnpm build:components"' packages/ui-react/package.json >packages/ui-react/package.json.tmp &&
			mv packages/ui-react/package.json.tmp packages/ui-react/package.json
		log_info "  Added root and styles.css exports, type:module, and build script to packages/ui-react/package.json"
	fi

	if [ -d "packages/ui-react/src" ]; then
		# Create Button component (referenced by sample stories)
		cat >packages/ui-react/src/button.tsx <<'EOF'
import { type ButtonHTMLAttributes } from 'react'

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
	variant?: 'primary' | 'secondary' | 'outline' | 'ghost'
	size?: 'sm' | 'md' | 'lg'
	children: React.ReactNode
}

const variantClasses: Record<NonNullable<ButtonProps['variant']>, string> = {
	primary: 'ui:bg-blue-600 ui:text-white hover:ui:bg-blue-700',
	secondary: 'ui:bg-neutral-600 ui:text-white hover:ui:bg-neutral-700',
	outline: 'ui:border ui:border-neutral-600 ui:text-neutral-100 hover:ui:bg-neutral-800',
	ghost: 'ui:text-neutral-100 hover:ui:bg-neutral-800',
}

const sizeClasses: Record<NonNullable<ButtonProps['size']>, string> = {
	sm: 'ui:px-3 ui:py-1.5 ui:text-sm',
	md: 'ui:px-4 ui:py-2 ui:text-base',
	lg: 'ui:px-6 ui:py-3 ui:text-lg',
}

export function Button({
	variant = 'primary',
	size = 'md',
	children,
	className = '',
	disabled,
	...props
}: ButtonProps) {
	return (
		<button
			className={[
				'ui:inline-flex ui:items-center ui:justify-center ui:rounded-md ui:font-medium ui:transition-colors ui:cursor-pointer',
				'disabled:ui:opacity-50 disabled:ui:cursor-not-allowed',
				variantClasses[variant],
				sizeClasses[size],
				className,
			].join(' ')}
			disabled={disabled}
			{...props}
		>
			{children}
		</button>
	)
}
EOF
		log_info "  Created packages/ui-react/src/button.tsx"

		# Generate barrel export from all .tsx files (excluding styles)
		{
			echo "// Auto-generated barrel export"
			find packages/ui-react/src -name "*.tsx" | sort | while read -r f; do
				base="$(basename "$f" .tsx)"
				echo "export * from './${base}.js'"
			done
		} >packages/ui-react/src/index.ts
		log_info "  Created packages/ui-react/src/index.ts"
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
- "msw"
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
minimumReleaseAge: 1440

# Shai-hulud 1: detected in 2.5 hours
# Shai-hulud 2: detected in 12 hours
# We're not always on the absolute latest versions of packages—despite best efforts.
# So this cooldown policy aligns more with our reality than it disrupts it.

minimumReleaseAgeExclude:
# - next
# - "@next/env"
# - turbo
- "@chromatic-com/storybook"
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
