target("Pong")
    set_kind("binary")
    set_languages("cxx23")

    add_includedirs("./src")
    add_files("./src/**.cpp")

    add_packages("oxylus")

    add_files("./Assets/**")
    add_rules("@oxylus/install_resources", {
        root_dir = os.scriptdir() .. "/Resources",
        output_dir = "Resources",
    })
    add_rules("@oxylus/install_shaders", {
        output_dir = "Resources/Shaders",
    })
target_end()
