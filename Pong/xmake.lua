target("Pong")
    set_kind("binary")
    set_languages("cxx23")
    -- Release builds ship their shared deps next to the executable, so look there first.
    if is_plat("linux") then
        add_rpathdirs("$ORIGIN")
    else
        add_rpathdirs("@executable_path")
    end

    add_includedirs(".")
    add_files("./src/**.cpp")

    add_packages("oxylus")

    -- the C# scripts are built by publish_csharp, not as sources of the game
    add_files("./Assets/**|.DS_Store|**/.DS_Store|.cooked/**|**.cs")
    add_rules("@oxylus/install_resources", {
        root_dir = os.scriptdir() .. "/Assets",
        output_dir = "Assets",
    })
    add_rules("@oxylus/install_shaders", {
        output_dir = "Assets/Shaders",
    })
    -- Assets/game.toml -> Assets/Shaders/game.oxpack, loaded by Game::init.
    add_files("./Assets/*.toml")
    add_rules("@oxylus/compile_shaders", {
        output_dir = "Assets/Shaders",
    })
    add_rules("@oxylus/cook_assets", { root_dir = os.scriptdir() .. "/Assets" })
    -- Scripts/Pong.csproj with NativeAOT -> scripts/Pong.dll, which App.cpp hands DotNetScripting
    add_rules("@oxylus/publish_csharp", {
        project = os.scriptdir() .. "/Scripts/Pong.csproj",
        asset_dir = os.scriptdir() .. "/Assets",
    })
target_end()
