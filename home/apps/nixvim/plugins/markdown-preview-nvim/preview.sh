# preview FILE — render FILE through :MarkdownPreview in Brave, then quit
# nvim, leaving the rendered tab behind.
#
# We override mkdp#rpc#stop_server / mkdp#rpc#preview_close to no-ops so the
# VimLeave / BufHidden close paths don't RPC close_all_pages over the websocket
# (which is what would tell the frontend to call window.close()). Plain socket
# disconnect just `console.log`s on the page.

if [ "$#" -ne 1 ]; then
	printf 'usage: preview FILE\n' >&2
	exit 2
fi

file=$(realpath -- "$1")
if [ ! -r "$file" ]; then
	printf 'preview: cannot read: %s\n' "$file" >&2
	exit 1
fi

# NB: '--' goes at the END so the -c flags are parsed as flags. With
# '-- "$file"' before them, nvim treats every -c token as a filename.
exec timeout 30 @nvim@ --headless \
	-c 'if &filetype == "" | setlocal filetype=markdown | endif' \
	-c 'silent MarkdownPreview' \
	-c 'lua if not vim.wait(15000, function() return vim.g.mkdp_clients_active == 1 end, 50) then io.stderr:write("preview: browser did not connect within 15s\n"); vim.cmd("cq 1") end' \
	-c 'sleep 500m' \
	-c 'lua vim.cmd("function! mkdp#rpc#stop_server() abort\nendfunction\nfunction! mkdp#rpc#preview_close() abort\nendfunction")' \
	-c 'qa' \
	-- "$file"
