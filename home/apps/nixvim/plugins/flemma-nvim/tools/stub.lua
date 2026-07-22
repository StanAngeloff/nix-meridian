--- Human-relay ("stub") tools for Flemma, declared per-buffer from frontmatter.
---
--- This module is a *template populator* — Flemma's public seam for contributing
--- globals to the sandboxed frontmatter (and `{{ }}`) environment. It injects a
--- `tools` global exposing `tools.stub(name, spec)`.
---
--- A stub is a tool the *model* can call but a *human* fulfils by hand. It is
--- pinned to manual approval, so the call lands as an EMPTY `(pending)`
--- tool_result that pauses autopilot. You run the request through an external
--- system (Claude Code, Perplexity, …), paste the report into the block, and
--- press <C-]> — content-overwrite protection sends your text as the result.
--- The tool's own `execute` is never reached in that flow.
---
--- Wire it once, globally:
---   require("flemma").setup({ templating = { modules = { "flemma-nvim.tools.stub" } } })
--- Then declare bespoke relays in any .chat file's frontmatter:
---   tools.stub("investigate_codebase", { description = "…", input_schema = { … } })
---
--- Nothing in Flemma's source changes — this lives entirely in your config.
---@class FlemmaStub : flemma.templating.Populator
local M = {}

local approval = require("flemma.tools.approval")
local registry = require("flemma.tools.registry")
local tools = require("flemma.tools")

-- Read env fields with rawget: the frontmatter sandbox installs a strict
-- __index that ERRORS on unknown names, and this same populator also runs for
-- the `{{ }}` message-body env (where `flemma` is absent).
local rawget = rawget

--- Names registered as stubs, so the approval resolver can pin them to manual.
---@type table<string, boolean>
local stub_names = {}

local RESOLVER_NAME = "flemma-nvim.tools.stub.force_manual"
local resolver_registered = false

--- Pin every stub to manual approval, overriding config. Priority > 100 beats
--- the config resolver (100) and the `require_approval = false` catch-all (0),
--- so a stub is ALWAYS `(pending)` — the gap the human fills.
local function ensure_resolver()
  if resolver_registered then
    return
  end
  approval.register(RESOLVER_NAME, {
    priority = 200,
    description = "Force manual approval for stub (human-relay) tools",
    resolve = function(tool_name)
      if stub_names[tool_name] then
        return "require_approval"
      end
      return nil
    end,
  })
  resolver_registered = true
end

--- Build the tool definition the model sees. `spec` is close to a raw tool
--- definition; the factory supplies the human-relay plumbing.
---@param name string
---@param spec { description: string, input_schema: table, strict?: boolean, format_preview?: fun(input: table): any }
---@return flemma.tools.ToolDefinition
local function build_definition(name, spec)
  assert(type(name) == "string" and name ~= "", "tools.stub: name must be a non-empty string")
  assert(type(spec) == "table", "tools.stub: spec must be a table")
  assert(type(spec.description) == "string" and spec.description ~= "", "tools.stub: spec.description is required")
  assert(type(spec.input_schema) == "table", "tools.stub: spec.input_schema must be a JSON Schema table")

  return {
    name = name,
    description = spec.description,
    input_schema = spec.input_schema,
    strict = spec.strict == true,
    -- Registered but kept OUT of the default tool list, so a stub is only
    -- active in the buffer whose frontmatter declared it (see populate()).
    enabled = false,
    async = false,
    -- Output is human-provided; a save_to redirect makes no sense for a stub.
    capabilities = { "disables_save_to" },
    format_preview = spec.format_preview,
    -- Only reached via a manual force-run (Alt-Enter); the normal flow never
    -- executes a stub. Kept as a self-explaining fallback.
    execute = function()
      return {
        success = false,
        error = "This is a manual stub tool. Run its request through the external system "
          .. "yourself, paste the report into this result block, and press <C-]> to send it.",
      }
    end,
  }
end

--- Register a single stub and activate it for the current buffer.
---@param env table The frontmatter sandbox env (read at call time, not capture time)
---@param name string Tool name the model calls
---@param spec { description: string, input_schema: table, strict?: boolean, format_preview?: fun(input: table): any }
local function register_stub(env, name, spec)
  if registry.has(name) then
    registry.unregister(name)
  end
  tools.register(name, build_definition(name, spec))
  stub_names[name] = true
  ensure_resolver()

  local flemma = rawget(env, "flemma")
  local opt = flemma and flemma.opt
  if opt and opt.tools then
    pcall(function()
      opt.tools:append(name)
    end)
  end
end

--- Populator entry point: inject the `tools` global into the frontmatter env.
---@param env table
function M.populate(env)
  env.tools = {
    --- Declare a human-relay tool, active for the current buffer only.
    ---@param name string Tool name the model calls
    ---@param spec { description: string, input_schema: table, strict?: boolean, format_preview?: fun(input: table): any }
    stub = function(name, spec)
      register_stub(env, name, spec)
    end,

    --- Load stub definitions from a Lua file, resolved against the .chat file's
    --- directory. The file must return a table — either keyed by tool name:
    ---   return { investigate = { description = "…", input_schema = {…} } }
    --- or as an array where each entry has a `name` field:
    ---   return { { name = "investigate", description = "…", input_schema = {…} } }
    ---@param path string File path, resolved relative to the .chat file's directory
    stubs_from = function(path)
      local dirname = rawget(env, "__dirname")
      assert(dirname, "tools.stubs_from: cannot resolve path — buffer has no file location")

      local resolved = path
      if path:sub(1, 1) ~= "/" then
        resolved = dirname .. "/" .. path
      end
      resolved = vim.fs.normalize(resolved)

      local chunk, load_err = loadfile(resolved)
      assert(chunk, "tools.stubs_from: " .. resolved .. ": " .. (load_err or "file not found"))

      local ok, definitions = pcall(chunk)
      assert(ok, "tools.stubs_from: " .. resolved .. ": " .. tostring(definitions))
      assert(type(definitions) == "table", "tools.stubs_from: file must return a table")

      for key, value in pairs(definitions) do
        if type(key) == "number" then
          assert(type(value.name) == "string", "tools.stubs_from: array entry missing 'name'")
          register_stub(env, value.name, value)
        else
          register_stub(env, key, value)
        end
      end
    end,
  }
end

M.name = "flemma-nvim.tools.stub"
M.priority = 500

return M
