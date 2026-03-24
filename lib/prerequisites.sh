#!/usr/bin/env bash

# =============================================================================
# Prerequisites Module
# =============================================================================
# Functions for checking and installing required tools:
# - pnpm (package manager)
# - yq (YAML processor)
# - jq (JSON processor)
# - Node.js (runtime)

check_pnpm() {
	log_info "Checking for pnpm installation..."

	if ! command -v pnpm &>/dev/null; then
		log_warning "pnpm not found"

		if command -v brew &>/dev/null; then
			log_info "Homebrew found, installing pnpm via Homebrew..."
			brew install pnpm
		elif command -v corepack &>/dev/null; then
			log_info "Corepack found, enabling pnpm..."
			corepack enable
			corepack prepare pnpm@latest --activate
		else
			log_info "Installing pnpm via install script..."
			curl -fsSL https://get.pnpm.io/install.sh | sh -
		fi

		# Update PATH for common pnpm install locations instead of sourcing shell rc files
		# (sourcing rc files can execute arbitrary user-defined code)
		export PATH="$HOME/.local/share/pnpm:$HOME/Library/pnpm:$HOME/.pnpm:$PATH"

		if ! command -v pnpm &>/dev/null; then
			log_warning "pnpm installed but not found in PATH. Please restart your shell or add pnpm to your PATH manually."
		fi
	else
		log_info "pnpm is already installed, upgrading to latest version"
		if command -v brew &>/dev/null; then
			log_info "Homebrew found, upgrading pnpm..."
			brew upgrade pnpm
		elif command -v corepack &>/dev/null; then
			log_info "Corepack found, updating pnpm..."
			corepack enable
			corepack prepare pnpm@latest --activate
		else
			log_info "Updating pnpm via install script..."
			curl -fsSL https://get.pnpm.io/install.sh | sh -
		fi
	fi

	PNPM_VERSION=$(pnpm --version)

	log_success "pnpm $PNPM_VERSION ready."
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

prepare_node() {
	log_info "Using Node LTS..."

	# Use pnpm to manage node version if possible, or just log
	if command -v pnpm &>/dev/null; then
		pnpm env use --global lts || log_warning "Failed to set global node version with pnpm, continuing with current version."
	fi

	log_success "Node LTS installed and in use"
}
