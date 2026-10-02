add_repositories("oxylus https://github.com/oxylusengine/xmake-repo.git")
set_policy("package.precompiled", false)
add_rules("mode.debug", "mode.release", "mode.dist")
add_rules("plugin.compile_commands.autoupdate", { outputdir = "./build", lsp = "clangd" })

set_project("Pong")
set_version("1.0.0")

-- GLOBAL COMPILER FLAGS --
set_encodings("utf-8")
add_cxxflags("clang::-fexperimental-library")

-- WARNINGS --
set_warnings("allextra", "pedantic")
add_cxxflags(
  "-Wshadow",
  "-Wno-missing-braces",
  "-Wno-unused-parameter",
  "-Wno-unused-variable",
  { tools = { "clang", "clangxx", "gcc" } }
)
add_cxxflags(
  "-Wshadow-all",
  "-Wno-gnu-line-marker",
  "-Wno-gnu-anonymous-struct",
  "-Wno-gnu-zero-variadic-macro-arguments",
  { tools = { "clang", "clangxx" } }
)

includes("xmake/rules.lua")

-- Off builds without engine.oxpack, game.oxpack or cooked assets, so the game can't run. CI uses it
-- for debug jobs, which are only compiled and never shipped.
option("compile_resources")
  set_default(true)
  set_showmenu(true)
  set_description("Compile shader packs and cook assets with rcli")
option_end()

add_requires("oxylus main", {
  debug = is_mode("debug"),
  configs = {
    lua_bindings = true,
    profile = false,
    tests = false,
    compile_resources = has_config("compile_resources"),
  },
})

includes("Pong")
includes("xmake/toolchains.lua")
