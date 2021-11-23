dofile(minetest.get_modpath("demoiselle") .. DIR_DELIM .. "demoiselle_global_definitions.lua")

--------------
-- Manual --
--------------

function demoiselle.getPlaneFromPlayer(player)
    local seat = player:get_attach()
    local plane = seat:get_attach()
    return plane
end

function demoiselle.pilot_formspec(name)
    local basic_form = table.concat({
        "formspec_version[3]",
        "size[6,4.5]",
	}, "")

	basic_form = basic_form.."button[1,1.0;4,1;go_out;Go Offboard]"
	basic_form = basic_form.."button[1,2.5;4,1;hud;Show/Hide Gauges]"

    minetest.show_formspec(name, "demoiselle:pilot_main", basic_form)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "demoiselle:pilot_main" then
        local name = player:get_player_name()
        local plane_obj = demoiselle.getPlaneFromPlayer(player)
        local ent = plane_obj:get_luaentity()
        if fields.hud then
            if ent._show_hud == true then
                ent._show_hud = false
            else
                ent._show_hud = true
            end
        end
		if fields.go_out then
            demoiselle.dettachPlayer(ent, player)
		end
        minetest.close_formspec(name, "demoiselle:pilot_main")
    end
end)
