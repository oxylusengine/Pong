rule("mode.dist")
    on_config(function (target)

        -- is release mode now? xmake f -m release
        if is_mode("dist") then

            -- set the symbols visibility: hidden
            if not target:get("symbols") and target:kind() ~= "shared" then
                target:set("symbols", "hidden")
            end

            -- enable optimization
            if not target:get("optimize") then
                if target:is_plat("android", "iphoneos") then
                    target:set("optimize", "smallest")
                else
                    target:set("optimize", "fastest")
                end
            end

            -- strip all symbols
            if not target:get("strip") then
                target:set("strip", "all")
            end

            -- enable NDEBUG macros to disables standard-C assertions
            target:add("cxflags", "-DNDEBUG")
            target:add("cuflags", "-DNDEBUG")
        end
    end)
