--- ### Nvim general utils
--
--  DESCRIPTION:
--  General utility functions to use within Nvim.

--    Helpers:
--      -> extend_tbl            → Add the content of a table to another table.
--      -> conditional_func      → Run a function if conditions are met.
--      -> get_icon              → Return an icon from the icons directory.
--      -> notify                → Send a notification asynchronously.
--      -> trigger_event         → Manually execute a user event.
--      -> system_open           → Open the file or URL under the cursor.
--      -> toggle_term_cmd       → get/set a re-usable toggleterm session.
--      -> is_available          → Return true if the plugin is available.
--      -> plugin_opts           → Return a plugin opts table.
--      -> load_plugin_with_func → Load a plugin before running a command.
--      -> which_key_register    → When setting a mapping, add it to whichkey.
--      -> empty_map_table       → Return a mappings table.
--      -> set_mappings          → We use it to create mappings in a clean way.
--      -> delete_url_effect     → Don't show an effect for urls.
--      -> set_url_effect        → Show an effect for urls.
--      -> cmd                   → Run a shell command and return true/false
--      -> is_big_file           → Return true if the file is too big.
--      -> os_path               → Convert the current path to the current OS.
--      -> confirm_quit          → Ask for confirmation before exit.

local M = {}

--- Merge extended options with a default table of options
---@param default? table The default table that you want to merge into
---@param opts? table The new options that should be merged with the default table
---@return table # The merged table
function M.extend_tbl(default, opts)
  opts = opts or {}
  return default and vim.tbl_deep_extend("force", default, opts) or opts
end

--- Call function if a condition is met.
---@param func function The function to run.
---@param condition boolean # Whether to run the function or not.
---@return any|nil result # the result of the function running or nil.
function M.conditional_func(func, condition, ...)
  -- if the condition is true or no condition is provided, evaluate
  -- the function with the rest of the parameters and return the result
  if condition and type(func) == "function" then return func(...) end
end

--- Get an icon from `lspkind` if it is available and return it.
---@param kind string The kind of icon in `lspkind` to retrieve.
---@return string icon.
function M.get_icon(kind, padding, no_fallback)
  if not vim.g.icons_enabled and no_fallback then return "" end
  local icon_pack = vim.g.icons_enabled and "icons" or "text_icons"
  if not M[icon_pack] then
    M.icons = require "base.icons.nerd_font"
    M.text_icons = require "base.icons.text"
  end
  local icon = M[icon_pack] and M[icon_pack][kind]
  return icon and icon .. string.rep(" ", padding or 0) or ""
end

--- Serve a notification with a title of Neovim.
---@param msg string The notification body.
---@param type number|nil The type of the notification (:help vim.log.levels).
---@param opts? table The nvim-notify options to use (:help notify-options).
function M.notify(msg, type, opts)
  vim.schedule(function() vim.notify(
    msg, type, M.extend_tbl({ title = "Neovim" }, opts)) end)
end

--- Convenient wapper to save code when we Trigger events.
---@param event string Name of the event.
-- @usage To run a User event:   `trigger_event("User MyUserEvent")`
-- @usage To run a Neovim event: `trigger_event("BufEnter")`
function M.trigger_event(event)
  -- detect if event start with the substring "User "
  local is_user_event = string.match(event, "^User ") ~= nil

  vim.schedule(function()
    if is_user_event then
      -- Substract the substring "User " from the beginning of the event.
      event = event:gsub("^User ", "")
      vim.api.nvim_exec_autocmds("User", { pattern = event, modeline = false })
    else
      vim.api.nvim_exec_autocmds(event, { modeline = false })
    end
  end)
end

--- Open a URL under the cursor with the current operating system.
---@param path string The path of the file to open with the system opener.
function M.system_open(path)
  local cmd
  if vim.fn.has "win32" == 1 and vim.fn.executable "explorer" == 1 then
    cmd = { "cmd.exe", "/K", "explorer" }
  elseif vim.fn.has "unix" == 1 and vim.fn.executable "xdg-open" == 1 then
    cmd = { "xdg-open" }
  elseif
    (vim.fn.has "mac" == 1 or vim.fn.has "unix" == 1)
    and vim.fn.executable "open" == 1
  then
    cmd = { "open" }
  end
  if not cmd then
    M.notify("Available system opening tool not found!", vim.log.levels.ERROR)
  end
  vim.fn.jobstart(
    vim.fn.extend(cmd, { path or vim.fn.expand "<cfile>" }),
    { detach = true }
  )
end

--- Toggle a user terminal if it exists, if not then create a new one and save it.
---@param opts string|table A terminal command string or a table of options
---                         for Terminal:new() Check toggleterm.nvim
---                         documentation for table format.
function M.toggle_term_cmd(opts)
  local terms = {}
  -- if a command string is provided, create a table for Terminal:new() options
  if type(opts) == "string" then opts = { cmd = opts, hidden = true } end
  local num = vim.v.count > 0 and vim.v.count or 1
  -- if terminal doesn't exist yet, create it
  if not terms[opts.cmd] then terms[opts.cmd] = {} end
  if not terms[opts.cmd][num] then
    if not opts.count then opts.count = vim.tbl_count(terms) * 100 + num end
    if not opts.on_exit then
      opts.on_exit = function() terms[opts.cmd][num] = nil end
    end
    terms[opts.cmd][num] = require("toggleterm.terminal").Terminal:new(opts)
  end
  -- toggle the terminal
  terms[opts.cmd][num]:toggle()
end

--- Check if a plugin is defined in lazy. Useful with lazy loading
--- when a plugin is not necessarily loaded yet.
---@param plugin string The plugin to search for.
---@return boolean available # Whether the plugin is available.
function M.is_available(plugin)
  local lazy_config_avail, lazy_config = pcall(require, "lazy.core.config")
  return lazy_config_avail and lazy_config.spec.plugins[plugin] ~= nil
end

--- Resolve the options table for a given plugin with lazy
---@param plugin string The plugin to search for
---@return table opts # The plugin options
function M.plugin_opts(plugin)
  local lazy_config_avail, lazy_config = pcall(require, "lazy.core.config")
  local lazy_plugin_avail, lazy_plugin = pcall(require, "lazy.core.plugin")
  local opts = {}
  if lazy_config_avail and lazy_plugin_avail then
    local spec = lazy_config.spec.plugins[plugin]
    if spec then opts = lazy_plugin.values(spec, "opts") end
  end
  return opts
end

--- Helper function to require a module when running a function.
---@param plugin string The plugin to call `require("lazy").load` with.
---@param module table The system module where the functions live (e.g. `vim.ui`).
---@param func_names string|string[] The functions to wrap in
---                                  the given module (e.g. `{ "ui", "select }`).
function M.load_plugin_with_func(plugin, module, func_names)
  if type(func_names) == "string" then func_names = { func_names } end
  for _, func in ipairs(func_names) do
    local old_func = module[func]
    module[func] = function(...)
      module[func] = old_func
      require("lazy").load { plugins = { plugin } }
      module[func](...)
    end
  end
end

--- Register queued which-key mappings.
function M.which_key_register()
  if M.which_key_queue then
    local wk_avail, wk = pcall(require, "which-key")
    if wk_avail then
      for mode, registration in pairs(M.which_key_queue) do
        wk.register(registration, { mode = mode })
      end
      M.which_key_queue = nil
    end
  end
end

--- Get an empty table of mappings with a key for each map mode
---@return table<string,table> # a table with entries for each map mode
function M.empty_map_table()
  local maps = {}
  for _, mode in ipairs { "", "n", "v", "x", "s", "o", "!", "i", "l", "c", "t" } do
    maps[mode] = {}
  end
  if vim.fn.has "nvim-0.10.0" == 1 then
    for _, abbr_mode in ipairs { "ia", "ca", "!a" } do
      maps[abbr_mode] = {}
    end
  end
  return maps
end

--- Table based API for setting keybindings.
---@param map_table table A nested table where the first key is the vim mode,
---                       the second key is the key to map, and the value is
---                       the function to set the mapping to.
---@param base? table A base set of options to set on every keybinding.
function M.set_mappings(map_table, base)
  -- iterate over the first keys for each mode
  base = base or {}
  for mode, maps in pairs(map_table) do
    -- iterate over each keybinding set in the current mode
    for keymap, options in pairs(maps) do
      -- build the options for the command accordingly
      if options then
        local cmd = options
        local keymap_opts = base
        if type(options) == "table" then
          cmd = options[1]
          keymap_opts = vim.tbl_deep_extend("force", keymap_opts, options)
          keymap_opts[1] = nil
        end
        if not cmd or keymap_opts.name then -- if which-key mapping, queue it
          if not keymap_opts.name then keymap_opts.name = keymap_opts.desc end
          if not M.which_key_queue then M.which_key_queue = {} end
          if not M.which_key_queue[mode] then M.which_key_queue[mode] = {} end
          M.which_key_queue[mode][keymap] = keymap_opts
        else -- if not which-key mapping, set it
          vim.keymap.set(mode, keymap, cmd, keymap_opts)
        end
      end
    end
  end
  -- if which-key is loaded already, register
  if package.loaded["which-key"] then M.which_key_register() end
end

--- regex used for matching a valid URL/URI string
M.url_matcher =
  "\\v\\c%(%(h?ttps?|ftp|file|ssh|git)://|[a-z]+[@][a-z]+[.][a-z]+:)%([&:#*@~%_\\-=?!+;/0-9a-z]+%(%([.;/?]|[.][.]+)[&:#*@~%_\\-=?!+/0-9a-z]+|:\\d+|,%(%(%(h?ttps?|ftp|file|ssh|git)://|[a-z]+[@][a-z]+[.][a-z]+:)@![0-9a-z]+))*|\\([&:#*@~%_\\-=?!+;/.0-9a-z]*\\)|\\[[&:#*@~%_\\-=?!+;/.0-9a-z]*\\]|\\{%([&:#*@~%_\\-=?!+;/.0-9a-z]*|\\{[&:#*@~%_\\-=?!+;/.0-9a-z]*})\\})+"

--- Delete the syntax matching rules for URLs/URIs if set.
function M.delete_url_effect()
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == "HighlightURL" then vim.fn.matchdelete(match.id) end
  end
end

--- Add syntax matching rules for highlighting URLs/URIs.
function M.set_url_effect()
  M.delete_url_effect()
  if vim.g.url_effect_enabled then
    vim.fn.matchadd("HighlightURL", M.url_matcher, 15)
  end
end

--- Run a shell command and capture the output and if the command
--- succeeded or failed
---@param cmd string|string[] The terminal command to execute
---@param show_error? boolean Whether or not to show an unsuccessful command
---                           as an error to the user
---@return string|nil # The result of a successfully executed command or nil
function M.cmd(cmd, show_error)
  if type(cmd) == "string" then cmd = vim.split(cmd, " ") end
  if vim.fn.has "win32" == 1 then cmd = vim.list_extend({ "cmd.exe", "/C" }, cmd) end
  local result = vim.fn.system(cmd)
  local success = vim.api.nvim_get_vvar "shell_error" == 0
  if not success and (show_error == nil or show_error) then
    vim.api.nvim_err_writeln(("Error running command %s\nError message:\n%s"):format(table.concat(cmd, " "), result))
  end
  return success and result:gsub("[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "") or nil
end

--- Returns true if the file is considered a big file,
--- according to the criteria defined in `vim.g.big_file`.
---@param bufnr number|nil buffer number. 0 by default, which means current buf.
---@return boolean is_big_file true or false.
function M.is_big_file(bufnr)
  if bufnr == nil then bufnr = 0 end
  local filesize = vim.fn.getfsize(vim.api.nvim_buf_get_name(bufnr))
  local nlines = vim.api.nvim_buf_line_count(bufnr)
  local is_big_file = (filesize > vim.g.big_file.size)
    or (nlines > vim.g.big_file.lines)
  return is_big_file
end

---Given a string, convert 'slash' to 'inverted slash' if on windows, and vice versa on UNIX.
---Then return the resulting string.
---@param path string A path string.
---@return string|nil,nil path A path string formatted for the current OS.
function M.os_path(path)
  if path == nil then return nil end
  -- Get the platform-specific path separator
  local separator = package.config:sub(1,1)
  return string.gsub(path, '[/\\]', separator)
end

--- Always ask before exiting nvim, even if there is nothing to be saved.
function M.confirm_quit()
  local choice = vim.fn.confirm("Do you really want to exit nvim?", "&Yes\n&No", 2)
  if choice == 1 then
    -- If user confirms, but there are still files to be saved: Ask
    vim.cmd('confirm quit')
  end
end



return M
