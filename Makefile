.PHONY: default switch format

default:
	@echo "Usage: make [switch|format]"
	@echo "  switch - Rebuild and switch to the new NixOS configuration"
	@echo "  format - Format the Nix files in the repository"

switch:
	nix shell 'nixpkgs#nh' --command nh os switch --ask .

format:
	nix shell 'nixpkgs#treefmt' 'nixpkgs#nixfmt-rfc-style' 'nixpkgs#gawk' --command treefmt .
