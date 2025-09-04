.PHONY: format

format:
	nsx treefmt nixfmt-rfc-style gawk -- treefmt .
