-- gen-rust-licences [--check] [package...]: reproduces the licence texts of the Rust crates compiled into the native
-- modules (packages/<name>/native/Cargo.toml), which THIRD_PARTY_NOTICES only names. For each module it reads the
-- locked dependency graph (`cargo tree --locked --offline -e normal --target <t>` after `cargo fetch --locked`:
-- normal dependencies for each platform Hecate builds for, the targets of deny.toml, no build-only or development
-- crate), the licence files of each crate
-- in the cargo registry (LICENSE*, COPYING*, NOTICE*, UNICODE*, ...), and for two-face the licence files of its
-- embedded syntax definitions (the helper packages/doc/native/examples/acknowledgements.rs), and writes ONE
-- deterministic page per module: packages/<name>/native/LICENSES-rust.md (the release artefacts of the native
-- modules ship it). `--check` writes nothing and fails when a page differs from the generated one, which is what a
-- change of a Cargo.lock requires. Needs cargo and crates.io (the sources are fetched into the cargo registry).
local util = require("lib.util")
local rust = require("lib.rust_licences")

local PAGE = "LICENSES-rust.md"
local TASK = "gen-rust-licences"

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

-- The platforms Hecate builds for: `[graph] targets` of deny.toml (one list for the licence audit and these pages).
local function targets(root)
  local text = read(root .. "/deny.toml") or ""
  local body = text:match("\ntargets%s*=%s*%[(.-)%]")
  local list = {}
  for line in (body or ""):gmatch("[^\n]+") do
    local triple = line:gsub("#.*$", ""):match('"([^"]+)"')
    if triple then list[#list + 1] = triple end
  end
  return list
end

-- The licences the audit accepts: the `[licenses] allow` list of deny.toml (the one of the module when it has its own).
local function allowed_licences(root, crate_dir)
  local text = read(crate_dir .. "/deny.toml") or read(root .. "/deny.toml") or ""
  return rust.parse_allow_list(text)
end

local function registry_sources()
  local home = os.getenv("CARGO_HOME")
  if not home or home == "" then
    local user = util.is_windows() and os.getenv("USERPROFILE") or os.getenv("HOME")
    home = (user or ".") .. "/.cargo"
  end
  home = home:gsub("\\", "/")
  local dirs = {}
  for _, index in ipairs(util.list_dir(home .. "/registry/src")) do dirs[#dirs + 1] = home .. "/registry/src/" .. index end
  return dirs
end

local function find_source(registries, crate)
  for _, dir in ipairs(registries) do
    local path = ("%s/%s-%s"):format(dir, crate.name, crate.version)
    if util.is_dir(path) then return path end
  end
  return nil
end

-- Runs a command and returns its whole standard output (not trimmed: the helper output is length-prefixed).
local function run(command)
  local p = io.popen(command, "r")
  if not p then return nil end
  local out = p:read("a")
  local ok = p:close()
  return out, ok == true
end

-- The names of the manifest authors, without their e-mail addresses.
local function authors_of(source)
  local authors = rust.read_authors(read(source .. "/Cargo.toml") or "")
  return authors and (authors:gsub("%s*<[^>]*>", "")) or nil
end

local function package_name(manifest)
  return manifest:match("%[package%].-\nname%s*=%s*\"([^\"]+)\"") or manifest:match("^%[package%]\nname%s*=%s*\"([^\"]+)\"")
end

local function module_model(ctx, name, registries, platforms, problems)
  local directory = ("packages/%s/native"):format(name)
  local crate_dir = ctx.root .. "/" .. directory
  local manifest_path = crate_dir .. "/Cargo.toml"
  local lock = read(crate_dir .. "/Cargo.lock")
  if not lock then
    problems[#problems + 1] = directory .. "/Cargo.lock is missing (cargo generate-lockfile, then commit it)"
    return nil
  end
  local manifest = read(manifest_path) or ""
  local quoted = util.quote(manifest_path)
  local _, fetched = util.capture(("cargo fetch --locked --manifest-path %s 2>&1"):format(quoted))
  if not fetched then
    problems[#problems + 1] = directory .. ": cargo fetch --locked failed (is Cargo.lock up to date, is crates.io reachable?)"
    return nil
  end
  local lines = {}
  for _, target in ipairs(platforms) do
    local tree, listed = util.capture(('cargo tree --locked --offline -e normal --target %s --prefix none --format "{p}|{l}" --manifest-path %s 2>&1')
      :format(target, quoted))
    if not listed then
      problems[#problems + 1] = ("%s: cargo tree --target %s failed:\n%s"):format(directory, target, tree)
      return nil
    end
    lines[#lines + 1] = tree
  end
  local crates, problem = rust.parse_tree(table.concat(lines, "\n"))
  if not crates then
    problems[#problems + 1] = directory .. ": " .. problem
    return nil
  end
  local model = {
    module = package_name(manifest) or ("hecate-" .. name .. "-native"),
    directory = directory,
    task = TASK,
    lock_sha256 = rust.lock_digest(lock, require("lib.sha256").hex),
    crates = {},
  }
  local allowed = allowed_licences(ctx.root, crate_dir)
  local two_face
  for _, crate in ipairs(crates) do
    local label = ("%s: %s %s"):format(directory, crate.name, crate.version)
    local entry = { name = crate.name, version = crate.version, license = crate.license, proc_macro = crate.proc_macro,
      files = {} }
    local relied, why = rust.parse_expression(crate.license, allowed)
    if not relied then
      problems[#problems + 1] = ("%s: %s"):format(label, why)
    else
      entry.relied = relied
      local source = find_source(registries, crate)
      if not source then
        problems[#problems + 1] = label .. ": source not found in the cargo registry (cargo fetch --locked)"
      else
        for _, file in ipairs(util.list_dir(source)) do
          if rust.is_licence_file(file) and not util.is_dir(source .. "/" .. file) then
            local text = read(source .. "/" .. file)
            if text and text:find("%z") == nil then entry.files[#entry.files + 1] = { name = file, text = rust.normalise(text) } end
          end
        end
        if #entry.files == 0 then
          for _, id in ipairs(relied) do
            local text = rust.fallback_text(id)
            if text and not entry.fallback then
              entry.fallback = { id = id, text = text, authors = authors_of(source) }
            end
          end
          if not entry.fallback then
            problems[#problems + 1] = ("%s: ships no licence file and there is no standard text for %s"):format(label,
              table.concat(relied, ", "))
          end
        end
      end
    end
    if crate.name == "two-face" then two_face = crate end
    model.crates[#model.crates + 1] = entry
  end
  if two_face then
    local example = directory .. "/examples/acknowledgements.rs"
    if not util.exists(ctx.root .. "/" .. example) then
      problems[#problems + 1] = ("%s: two-face is a dependency and %s (its helper) is missing"):format(directory, example)
      return model
    end
    local out, ok = run(("cargo run --locked --offline -q --manifest-path %s --example acknowledgements"):format(quoted))
    if not ok or not out then
      problems[#problems + 1] = directory .. ": the helper acknowledgements failed to run"
      return model
    end
    local entries, why = rust.parse_acknowledgements(out)
    if not entries then
      problems[#problems + 1] = ("%s: %s"):format(directory, why)
      return model
    end
    model.syntaxes = { source = ("two-face %s"):format(two_face.version), entries = entries }
  end
  return model
end

return {
  description = "write the licence texts of the Rust crates of the native modules to packages/<name>/native/LICENSES-rust.md (--check to verify only)",
  run = function(ctx)
    local check, only = false, {}
    for _, a in ipairs(ctx.args) do
      if a == "--check" then check = true
      elseif a:sub(1, 1) == "-" then return { ok = false, problems = { "usage: gen-rust-licences [--check] [package...]" } }
      else only[#only + 1] = a end
    end
    local _, have_cargo = util.capture("cargo --version")
    if not have_cargo then return { ok = false, problems = { "cargo not found: install a Rust toolchain" } } end
    local names = {}
    for _, name in ipairs(util.list_dir(ctx.root .. "/packages")) do
      if util.exists(ctx.root .. "/packages/" .. name .. "/native/Cargo.toml") then names[#names + 1] = name end
    end
    if #only > 0 then
      names = {}
      for _, name in ipairs(only) do
        if not util.exists(ctx.root .. "/packages/" .. name .. "/native/Cargo.toml") then
          return { ok = false, problems = { ("no native Rust module in package '%s'"):format(name) } }
        end
        names[#names + 1] = name
      end
    end
    local platforms = targets(ctx.root)
    if #platforms == 0 then return { ok = false, problems = { "deny.toml: no [graph] targets" } } end
    local registries = registry_sources()
    local problems, data = {}, {}
    for _, name in ipairs(names) do
      local before = #problems
      local model = module_model(ctx, name, registries, platforms, problems)
      if model and #problems == before then
        local page = rust.render(model)
        local relative = ("packages/%s/native/%s"):format(name, PAGE)
        local path = ctx.root .. "/" .. relative
        local old = read(path)
        local state = old == page and "up to date" or "stale"
        if state == "stale" then
          if check then
            problems[#problems + 1] = ("%s is %s; run lua tools/run.lua %s"):format(relative,
              old and "out of date" or "missing", TASK)
          else
            local f, err = io.open(path, "wb")
            if not f then
              problems[#problems + 1] = ("%s: %s"):format(relative, tostring(err))
            else
              f:write(page)
              f:close()
              state = "written"
            end
          end
        end
        data[#data + 1] = { package = name, file = relative, state = state, crates = #model.crates, bytes = #page,
          syntax_licences = model.syntaxes and #model.syntaxes.entries or 0 }
      end
    end
    return { ok = #problems == 0, problems = problems, data = data }
  end,
}
