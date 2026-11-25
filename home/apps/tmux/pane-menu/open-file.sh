# tmux-open-file find <pane> x<pane path> x<hyperlink> x<word>: the right-click pane menu runs this just before it opens,
# with the hyperlink and the word under the pointer. The file or directory they name goes into the pane's @open-file-path,
# for the menu's Open entry; when they name none, the entry is greyed out.
# tmux-open-file open <pane>: the Open entry; xdg-open opens the file, as it does for a link Ghostty opens.
# The x before each value keeps an empty one from dropping out of the arguments.
mode="$1"
pane_id="$2"

if [[ "$mode" == open ]]; then
	open_path=$(tmux show -pqv -t "$pane_id" @open-file-path)
	if [[ -n "$open_path" ]]; then exec xdg-open "$open_path"; fi
	exit 0
fi

pane_path="${3#x}"
hyperlink="${4#x}"
word="${5#x}"

# A file:// hyperlink under the pointer comes before the word as printed.
candidates=()
if [[ "$hyperlink" == file://* ]]; then
	hyperlink_path="${hyperlink#file://}"
	hyperlink_path="/${hyperlink_path#*/}"
	candidates+=("$(printf '%b' "${hyperlink_path//%/\\x}")")
fi
if [[ -n "$word" ]]; then candidates+=("$word"); fi

# Prose wraps a name in brackets and quotes and ends a sentence on it, and tools add :line or :line:column.
# Those come off one character at a time until the name exists, so a name whose own last character is a dot still opens.
leading='"'\''`(<[{'
trailing='.,;:!?)]}>"'\''`'
found_path=""
try_path() {
	local path="$1"
	if [[ "$path" == \~/* ]]; then path="$HOME/${path#\~/}"; fi
	if [[ "$path" != /* ]]; then path="$pane_path/$path"; fi
	if [[ -e "$path" ]]; then found_path=$(realpath -s -- "$path"); fi
	[[ -n "$found_path" ]]
}
for candidate in "${candidates[@]}"; do
	try_path "$candidate" && break
	while [[ -n "$candidate" && "$leading" == *"${candidate:0:1}"* ]]; do candidate="${candidate:1}"; done
	while true; do
		try_path "$candidate" && break 2
		if [[ "$candidate" =~ ^(.+):[0-9]+(:[0-9]+)?$ ]]; then try_path "${BASH_REMATCH[1]}" && break 2; fi
		[[ -n "$candidate" && "$trailing" == *"${candidate: -1}"* ]] || break
		candidate="${candidate%?}"
	done
done

if [[ -z "$found_path" ]]; then
	tmux set -pu -t "$pane_id" @open-file-path \; set -pu -t "$pane_id" @open-file-label
	exit 0
fi

# The entry names the file from the pane's directory, or from ~.
label="$found_path"
if [[ "$label" == "$pane_path"/* ]]; then
	label="${label#"$pane_path"/}"
elif [[ "$label" == "$HOME"/* ]]; then
	label=\~/"${label#"$HOME"/}"
fi
tmux set -p -t "$pane_id" @open-file-path "$found_path" \; set -p -t "$pane_id" @open-file-label "$label"
