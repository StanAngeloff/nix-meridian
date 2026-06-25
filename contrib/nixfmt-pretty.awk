# A function to parse key-value options from a directive string.
# e.g., "as: shell-args, other: value"
# It populates a global associative array `fmt_options`.
function parse_fmt_options(options_str, pairs, kv, n, i, key, value) {
    # Clear any previous options before parsing.
    delete fmt_options

    # Trim leading/trailing whitespace from the whole options string.
    sub(/^\s*/, "", options_str)
    sub(/\s*$/, "", options_str)

    # Split the string by commas, allowing for whitespace around them.
    n = split(options_str, pairs, /\s*,\s*/)

    for (i = 1; i <= n; i++) {
        # Split each pair into a key and a value by the first colon.
        if (split(pairs[i], kv, /\s*:\s*/) == 2) {
            key = kv[1]
            value = kv[2]
            fmt_options[key] = value
        }
    }
}

# A function to count braces while ignoring those inside strings.
# It returns the net change in brace count for the line (e.g., +1, -1, 0).
# Local variables are declared in the function signature to keep them local.
function get_brace_delta(line, i, char, in_string, delta) {
    in_string = 0
    delta = 0

    for (i = 1; i <= length(line); ++i) {
        char = substr(line, i, 1)

        # If we see a quote, check if it's escaped. If not, flip the in_string state.
        # This simple check handles \" correctly.
        if (char == "\"") {
            if (i == 1 || substr(line, i - 1, 1) != "\\") { in_string = !in_string }
        }

        # Only count braces if we are NOT inside a string.
        if (!in_string) {
            if (char == "{") { delta++ }
            else if (char == "}") { delta-- }
        }
    }

    return delta
}

# A function to split a single collapsed line into top-level statements.
# It cuts on every ";" that sits at bracket-depth zero and outside a string,
# so a ";" nested inside "{ ... }" (e.g. "{ ghostty = prev.ghostty; }") stays
# attached to its statement. Each returned part keeps its trailing ";".
# Returns the number of parts and fills the `parts` array (1-indexed).
function split_top_level_statements(text, parts, i, char, in_string, depth, n, current) {
    delete parts
    in_string = 0
    depth = 0
    n = 0
    current = ""

    for (i = 1; i <= length(text); ++i) {
        char = substr(text, i, 1)

        # Track string state so brackets/semicolons inside strings are ignored.
        if (char == "\"") {
            if (i == 1 || substr(text, i - 1, 1) != "\\") { in_string = !in_string }
            current = current char
            continue
        }

        if (!in_string) {
            if (char == "{" || char == "(" || char == "[") { depth++ }
            else if (char == "}" || char == ")" || char == "]") { depth-- }

            # A semicolon at the top level closes the current statement.
            if (char == ";" && depth == 0) {
                parts[++n] = current char
                current = ""
                continue
            }
        }

        current = current char
    }

    # Keep any trailing remainder that was not terminated by a top-level ";".
    if (current ~ /\S/) { parts[++n] = current }

    return n
}

# Rule 1: Handle the "nixfmt: on" directive.
# This pattern has the highest priority to ensure it can turn off the active state.
/#\s*nixfmt:\s*on\>/ {
    # Parse any options present on the 'on' directive line.
    if (match($0, /#\s*nixfmt:\s*on\s*,(.*)/, m)) { parse_fmt_options(m[1]) }

    # If we are active but never processed a block, format the buffered section.
    if (active && !block_was_processed && section_buffer) {
        # Check for a specific formatting mode.
        if (fmt_options["as"] == "shell-args") {
            # Behavior for shell arguments: join lines, but create newlines for args starting with "--".
            output_line = ""
            split(section_buffer, lines, RS) # RS is the Record Separator (newline)

            for (i = 1; i <= length(lines); i++) {
                line = lines[i]

                if (line !~ /\S/) { continue } # Skip empty lines.

                sub(/^\s*/, "", line)
                sub(/\s*$/, "", line) # Trim the line

                if (line ~ /^"--/) {
                    if (output_line) { print section_indent output_line }

                    output_line = line
                }
                else { output_line = output_line " " line }
            }

            if (output_line) { print section_indent output_line }
        }
        else if (fmt_options["as"] == "list-of-calls") {
            # Behavior: For a list of function calls like (call1) (call2)
            # 1. Collapse the buffer into a single line.
            gsub(RS, " ", section_buffer)
            gsub(/\s+/, " ", section_buffer)
            sub(/^\s*/, "", section_buffer)
            sub(/\s*$/, "", section_buffer)

            # 2. Insert a newline between closing and opening parentheses.
            # This effectively splits by ") ("
            gsub(/\)\s*\(/, ")" RS "(", section_buffer)

            # 3. Print each resulting line with the proper section indent.
            split(section_buffer, lines, RS)
            for (i = 1; i <= length(lines); i++) {
                if (lines[i] ~ /\S/) {
                    print section_indent lines[i]
                }
            }
        }
        else if (fmt_options["as"] == "statements") {
            # Behavior: one statement per line. First collapse the whole buffer
            # into a single spaced line (re-joining anything nixfmt wrapped
            # within a statement), then split on top-level ";" so each
            # ";"-terminated statement — e.g. each attribute binding — lands on
            # its own line at the section indent.
            gsub(RS, " ", section_buffer)
            gsub(/\s+/, " ", section_buffer)
            sub(/^\s*/, "", section_buffer)
            sub(/\s*$/, "", section_buffer)

            statement_count = split_top_level_statements(section_buffer, statements)
            for (i = 1; i <= statement_count; i++) {
                statement = statements[i]
                sub(/^\s*/, "", statement)
                sub(/\s*$/, "", statement)
                if (statement ~ /\S/) { print section_indent statement }
            }
        }
        else {
            # Original/default behavior: collapse all lines into a single line.
            gsub(RS, " ", section_buffer) # Use RS instead of /\n/
            gsub(/\s+/, " ", section_buffer)
            sub(/^\s*/, "", section_buffer)
            sub(/\s*$/, "", section_buffer)
            print section_indent section_buffer
        }
    }

    print # Print the directive itself
    active = 0 # Turn off the active state

    # Reset block-parsing state in case of a malformed file
    in_block = 0
    buffer = ""
    brace_count = 0
    indent = ""
    block_was_processed = 0
    section_buffer = ""
    section_indent = ""
    delete fmt_options # Clear parsed options for the next section.

    next # Move to the next line immediately
}

# Rule 2: Handle the "nixfmt: off" directive.
/#\s*nixfmt:\s*off\>/ {
    print # Print the directive itself
    active = 1 # Turn on the active state
    block_was_processed = 0
    section_buffer = ""
    section_indent = ""
    next # Move to the next line
}

# Rule 3: Process lines when in active mode, but not yet inside a { ... } block.
active && !in_block {
    # If the line is just an opening brace, start a new block.
    if (/^\s*{\s*$/) {
        # If there were lines buffered before this block, print them now.
        if (!block_was_processed && section_buffer) { print section_buffer }

        # Mark that we have now found a block, so we won't collapse the whole section.
        block_was_processed = 1

        # Capture the leading whitespace (indentation) of this line.
        match($0, /^\s*/)
        indent = substr($0, RSTART, RLENGTH)

        in_block = 1
        brace_count = 1
        buffer = $0 # Start the buffer with the opening brace
    }
    else {
        # If a block has already been processed, print subsequent lines (like comments) normally.
        if (block_was_processed) { print }
        else {
            # Otherwise, buffer the line in case we need to collapse the whole section later.
            # Only capture indentation from the first non-empty line of the section.
            if (!section_buffer && /\S/) {
                match($0, /^\s*/)
                section_indent = substr($0, RSTART, RLENGTH)
            }

            # Buffer the line, preserving newlines (RS is the Record Separator).
            section_buffer = (section_buffer ? section_buffer RS : "") $0
        }
    }

    next # Move to the next line
}

# Rule 4: Process lines when we are actively inside a { ... } block.
active && in_block {
    # Append the current line to our buffer, separated by a space.
    buffer = buffer " " $0

    # Count the braces on the current line to track nesting.
    brace_count += get_brace_delta($0)

    # Check if the braces are balanced (i.e., the block is complete).
    if (brace_count == 0) {
        # The block is finished, so process and print the buffer.

        # 1. Collapse all sequences of whitespace into a single space.
        gsub(/\s+/, " ", buffer)

        # 2. Trim leading and trailing whitespace from the final string.
        sub(/^\s*/, "", buffer)
        sub(/\s*$/, "", buffer)

        print indent buffer

        # Reset the block state for the next potential block.
        in_block = 0
        buffer = ""
        indent = ""
        # Mark that a block was successfully processed.
        block_was_processed = 1
    }

    next # Move to the next line
}

# Rule 5: Default action.
# This runs for any line that wasn't handled by the rules above.
# Primarily, this prints lines when `active` is false.
{ print }
