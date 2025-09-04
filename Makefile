.PHONY: default switch format

SUDO ?= sudo

default:
	@echo "Usage: make [switch|format]"
	@echo "  switch - Rebuild and switch to the new NixOS configuration"
	@echo "  format - Format the Nix files in the repository"

switch:
	$(SUDO) nixos-rebuild switch --show-trace

format:
	nsx treefmt nixfmt-rfc-style gawk -- treefmt .
