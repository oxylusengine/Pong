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

    add_files("./Assets/**")
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
    add_rules("@oxylus/install_fonts", {
        output_dir = "Assets/Fonts",
    })
target_end()
