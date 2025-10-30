add_repositories("oxylus https://github.com/oxylusengine/xmake-repo.git")
set_policy("package.precompiled", false)
add_rules("mode.debug", "mode.release", "mode.dist")
add_rules("plugin.compile_commands.autoupdate", { outputdir = ".", lsp = "clangd" })

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
    { tools = { "clang", "clangxx", "gcc" } })
add_cxxflags(
    "-Wshadow-all",
    "-Wno-gnu-line-marker",
    "-Wno-gnu-anonymous-struct",
    "-Wno-gnu-zero-variadic-macro-arguments",
    { tools = { "clang", "clangxx" } })

includes("xmake/rules.lua")
includes("xmake/options.lua")

add_requires("oxylus 9e646d9a5ada08b2396c915c21d7b6b950851445", { debug = is_mode("debug"), configs = {
    lua_bindings = true,
    profile = is_mode("debug"),
    tests = false,
} })

includes("Pong")
includes("xmake/toolchains.lua")