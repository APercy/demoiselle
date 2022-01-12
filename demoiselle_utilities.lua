dofile(minetest.get_modpath("demoiselle") .. DIR_DELIM .. "demoiselle_global_definitions.lua")
dofile(minetest.get_modpath("demoiselle") .. DIR_DELIM .. "demoiselle_hud.lua")

function demoiselle.get_hipotenuse_value(point1, point2)
    return math.sqrt((point1.x - point2.x) ^ 2 + (point1.y - point2.y) ^ 2 + (point1.z - point2.z) ^ 2)
end

function demoiselle.dot(v1,v2)
	return v1.x*v2.x+v1.y*v2.y+v1.z*v2.z
end

function demoiselle.sign(n)
	return n>=0 and 1 or -1
end

function demoiselle.minmax(v,m)
	return math.min(math.abs(v),m)*demoiselle.sign(v)
end

--lift
local function pitchroll2pitchyaw(aoa,roll)
	if roll == 0.0 then return aoa,0 end
	-- assumed vector x=0,y=0,z=1
	local p1 = math.tan(aoa)
	local y = math.cos(roll)*p1
	local x = math.sqrt(p1^2-y^2)
	local pitch = math.atan(y)
	local yaw=math.atan(x)*math.sign(roll)
	return pitch,yaw
end

function demoiselle.getLiftAccel(self, velocity, accel, longit_speed, roll, curr_pos)
    --lift calculations
    -----------------------------------------------------------
    local max_height = 7000
    
    local retval = accel
    if longit_speed > 1 then
        local angle_of_attack = math.rad(self._angle_of_attack + demoiselle.wing_angle_of_attack)
        local lift = demoiselle.lift
        --local acc = 0.8
        local daoa = deg(angle_of_attack)

        --to decrease the lift coefficient at hight altitudes
        local curr_percent_height = (100 - ((curr_pos.y * 100) / max_height))/100

	    local rotation=self.object:get_rotation()
	    local vrot = mobkit.dir_to_rot(velocity,rotation)
	    
	    local hpitch,hyaw = pitchroll2pitchyaw(angle_of_attack,roll)

	    local hrot = {x=vrot.x+hpitch,y=vrot.y-hyaw,z=roll}
	    local hdir = mobkit.rot_to_dir(hrot) --(hrot)
	    local cross = vector.cross(velocity,hdir)
	    local lift_dir = vector.normalize(vector.cross(cross,hdir))

        local lift_coefficient = (0.24*abs(daoa)*(1/(0.025*daoa+3))^4*math.sign(angle_of_attack))
        local lift_val = math.abs((lift*(vector.length(velocity)^2)*lift_coefficient)*curr_percent_height)
        --minetest.chat_send_all('lift: '.. lift_val)

        local lift_acc = vector.multiply(lift_dir,lift_val)
        --lift_acc=vector.add(vector.multiply(minetest.yaw_to_dir(rotation.y),acc),lift_acc)

        retval = vector.add(retval,lift_acc)
    end
    -----------------------------------------------------------
    -- end lift
    return retval
end


function demoiselle.get_gauge_angle(value, initial_angle)
    initial_angle = initial_angle or 90
    local angle = value * 18
    angle = angle - initial_angle
    angle = angle * -1
	return angle
end

-- attach player
function demoiselle.attach(self, player, instructor_mode)
    instructor_mode = instructor_mode or false
    local name = player:get_player_name()
    self.driver_name = name

    -- attach the driver
    if instructor_mode == true then
        player:set_attach(self.passenger_seat_base, "", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
        player:set_eye_offset({x = 0, y = -2.5, z = 2}, {x = 0, y = 1, z = -30})
    else
        player:set_attach(self.pilot_seat_base, "", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
        player:set_eye_offset({x = 0, y = -4, z = 2}, {x = 0, y = 1, z = -30})
    end
    player:set_eye_offset({x = 0, y = -4, z = 2}, {x = 0, y = 1, z = -30})
    player_api.player_attached[name] = true
    -- make the driver sit
    minetest.after(0.2, function()
        player = minetest.get_player_by_name(name)
        if player then
	        player_api.set_animation(player, "sit")
            --apply_physics_override(player, {speed=0,gravity=0,jump=0})
        end
    end)
end

function demoiselle.dettachPlayer(self, player)
    local name = self.driver_name
    demoiselle.setText(self)

    demoiselle.remove_hud(player)

    --self._engine_running = false

    -- driver clicked the object => driver gets off the vehicle
    self.driver_name = nil

    if self._engine_running then
	    self._engine_running = false
        self.engine:set_animation_frame_speed(0)
    end
    -- sound and animation
    if self.sound_handle then
        minetest.sound_stop(self.sound_handle)
        self.sound_handle = nil
    end

    -- detach the player
    player:set_detach()
    player_api.player_attached[name] = nil
    player:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
    player_api.set_animation(player, "stand")
    self.driver = nil
    --remove_physics_override(player, {speed=1,gravity=1,jump=1})
end

function demoiselle.checkAttach(self, player)
    if player then
        local player_attach = player:get_attach()
        if player_attach then
            if player_attach == self.pilot_seat_base or player_attach == self.passenger_seat_base then
                return true
            end
        end
    end
    return false
end

-- destroy the boat
function demoiselle.destroy(self)
    if self._engine_running then
	    self._engine_running = false
        self.engine:set_animation_frame_speed(0)
    end
    -- sound and animation
    if self.sound_handle then
        minetest.sound_stop(self.sound_handle)
        self.sound_handle = nil
    end

    if self.driver_name then
        -- detach the driver
        local player = minetest.get_player_by_name(self.driver_name)
        demoiselle.dettachPlayer(self, player)
    end

    local pos = self.object:get_pos()
    if self.engine then self.engine:remove() end
    if self.pilot_seat_base then self.pilot_seat_base:remove() end
    if self.stick then self.stick:remove() end

    self.object:remove()

    pos.y=pos.y+2
    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'demoiselle:wings')

    for i=1,6 do
	    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:steel_ingot')
    end

    for i=1,4 do
	    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:wood')
    end

    for i=1,6 do
	    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:mese_crystal')
    end

    --minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'demoiselle:demoiselle')
end

function demoiselle.check_node_below(obj)
    local pos_below = obj:get_pos()
    if pos_below then
        pos_below.y = pos_below.y - 2.5
        local node_below = minetest.get_node(pos_below).name
        local nodedef = minetest.registered_nodes[node_below]
        local touching_ground = not nodedef or -- unknown nodes are solid
		        nodedef.walkable or false
        local liquid_below = not touching_ground and nodedef.liquidtype ~= "none"
        return touching_ground, liquid_below
    end
    return nil, nil
end

function demoiselle.setText(self)
    local properties = self.object:get_properties()
    local formatted = string.format(
       "%.2f", self.hp_max
    )
    if properties then
        properties.infotext = "Nice demoiselle of " .. self.owner .. ". Current hp: " .. formatted
        self.object:set_properties(properties)
    end
end

function demoiselle.testImpact(self, velocity, position)
    local p = position --self.object:get_pos()
    local collision = false
    if self._last_vel == nil then return end
    --lets calculate the vertical speed, to avoid the bug on colliding on floor with hard lag
    if abs(velocity.y - self._last_vel.y) > 2 then
		local noded = mobkit.nodeatpos(mobkit.pos_shift(p,{y=-2.8}))
	    if (noded and noded.drawtype ~= 'airlike') then
		    collision = true
	    else
            self.object:set_velocity(self._last_vel)
            self.object:set_acceleration(self._last_accell)
        end
    end
    local impact = abs(demoiselle.get_hipotenuse_value(velocity, self._last_vel))
    --minetest.chat_send_all('impact: '.. impact .. ' - hp: ' .. self.hp_max)
    if impact > 2 then
        --minetest.chat_send_all('impact: '.. impact .. ' - hp: ' .. self.hp_max)
		local nodeu = mobkit.nodeatpos(mobkit.pos_shift(p,{y=1}))
		local noded = mobkit.nodeatpos(mobkit.pos_shift(p,{y=-2.8}))
        local nodel = mobkit.nodeatpos(mobkit.pos_shift(p,{x=-1}))
        local noder = mobkit.nodeatpos(mobkit.pos_shift(p,{x=1}))
        local nodef = mobkit.nodeatpos(mobkit.pos_shift(p,{z=1}))
        local nodeb = mobkit.nodeatpos(mobkit.pos_shift(p,{z=-1}))
		if (nodeu and nodeu.drawtype ~= 'airlike') or
            (nodef and nodef.drawtype ~= 'airlike') or
            (nodeb and nodeb.drawtype ~= 'airlike') or
            (noder and noder.drawtype ~= 'airlike') or
            (nodel and nodel.drawtype ~= 'airlike') then
			collision = true
		end
    end

    if collision then
        --self.object:set_velocity({x=0,y=0,z=0})
        local damage = impact / 2
        self.hp_max = self.hp_max - damage --subtract the impact value directly to hp meter
        minetest.sound_play("demoiselle_collision", {
            --to_player = self.driver_name,
            object = self.object,
            max_hear_distance = 15,
            gain = 1.0,
            fade = 0.0,
            pitch = 1.0,
        }, true)

        if self.driver_name then
            local player_name = self.driver_name
            demoiselle.setText(self)

            --minetest.chat_send_all('damage: '.. damage .. ' - hp: ' .. self.hp_max)
            if self.hp_max <= 0 then --if acumulated damage is greater than 50, adieu
                demoiselle.destroy(self)
            end

            local player = minetest.get_player_by_name(player_name)
            if player then
		        if player:get_hp() > 0 then
			        player:set_hp(player:get_hp()-(damage/2))
		        end
            end
            if self._passenger ~= nil then
                local passenger = minetest.get_player_by_name(self._passenger)
                if passenger then
		            if passenger:get_hp() > 0 then
			            passenger:set_hp(passenger:get_hp()-(damage/2))
		            end
                end
            end
        end

    end
end

function demoiselle.checkattachBug(self)
    -- for some engine error the player can be detached from the submarine, so lets set him attached again
    if self.owner and self.driver_name then
        -- attach the driver again
        local player = minetest.get_player_by_name(self.owner)
        if player then
		    if player:get_hp() > 0 then
                demoiselle.attach(self, player, self._instruction_mode)
            else
                demoiselle.dettachPlayer(self, player)
		    end
        end
    end
end

function demoiselle.check_is_under_water(obj)
	local pos_up = obj:get_pos()
	pos_up.y = pos_up.y + 0.1
	local node_up = minetest.get_node(pos_up).name
	local nodedef = minetest.registered_nodes[node_up]
	local liquid_up = nodedef.liquidtype ~= "none"
	return liquid_up
end

function demoiselle.flightstep(self)
    local velocity = self.object:get_velocity()
    --hack to avoid glitches
    local curr_pos = self.object:get_pos()

    self._last_time_command = self._last_time_command + self.dtime
    local player = nil
    if self.driver_name then player = minetest.get_player_by_name(self.driver_name) end

    if player then
        local ctrl = player:get_player_control()
        ----------------------------------
        -- shows the hud for the player
        ----------------------------------
        if ctrl.up == true and ctrl.down == true and self._last_time_command >= 1 then
            self._last_time_command = 0
            if self._show_hud == true then
                self._show_hud = false
            else
                self._show_hud = true
            end
        end
    end

    local accel_y = self.object:get_acceleration().y
    local rotation = self.object:get_rotation()
    local yaw = rotation.y
	local newyaw=yaw
    local pitch = rotation.x
	local roll = rotation.z
	local newroll=roll
    if newroll > 360 then newroll = newroll - 360 end
    if newroll < -360 then newroll = newroll + 360 end

    local hull_direction = mobkit.rot_to_dir(rotation) --minetest.yaw_to_dir(yaw)
    local nhdir = {x=hull_direction.z,y=0,z=-hull_direction.x}		-- lateral unit vector

    local longit_speed = vector.dot(velocity,hull_direction)
    self._longit_speed = longit_speed
    local longit_drag = vector.multiply(hull_direction,longit_speed*
            longit_speed*DEMOISELLE_LONGIT_DRAG_FACTOR*-1*demoiselle.sign(longit_speed))
	local later_speed = demoiselle.dot(velocity,nhdir)
    --minetest.chat_send_all('later_speed: '.. later_speed)
	local later_drag = vector.multiply(nhdir,later_speed*later_speed*
            DEMOISELLE_LATER_DRAG_FACTOR*-1*demoiselle.sign(later_speed))
    local accel = vector.add(longit_drag,later_drag)
    local stop = false

    local node_bellow = mobkit.nodeatpos(mobkit.pos_shift(curr_pos,{y=-0.1}))
    local is_flying = true
    if node_bellow and node_bellow.drawtype ~= 'airlike' then is_flying = false end
    --if is_flying then minetest.chat_send_all('is flying') end

    local is_attached = demoiselle.checkAttach(self, player)

    --ajustar angulo de ataque
    local percentage = math.abs(((longit_speed * 100)/(demoiselle.min_speed + 5))/100)
    if percentage > 1.5 then percentage = 1.5 end
    self._angle_of_attack = self._angle_of_attack - ((self._elevator_angle / 20)*percentage)
    if self._angle_of_attack < -0.5 then
        self._angle_of_attack = -0.1
        self._elevator_angle = self._elevator_angle - 0.1
    end --limiting the negative angle]]--
    if self._angle_of_attack > 20 then
        self._angle_of_attack = 20
        self._elevator_angle = self._elevator_angle + 0.1
    end --limiting the very high climb angle due to strange behavior]]--

    --minetest.chat_send_all(self._angle_of_attack)

    -- pitch
    local speed_factor = 0
    if longit_speed > demoiselle.min_speed + 1 then speed_factor = (velocity.y * math.rad(2)) end
    local newpitch = math.rad(self._angle_of_attack) + speed_factor

    -- adjust pitch at ground
    if is_flying == false then --isn't flying?
        if math.abs(longit_speed) < demoiselle.min_speed + 2 then
            --[[percentage = ((longit_speed * 100)/demoiselle.min_speed)/100
            if newpitch ~= 0 then
                newpitch = newpitch * percentage
            end]]--
            
            if speed_factor == 0 then
                self._angle_of_attack = 0
                new_pitch = math.rad(0)
            end

        end

        --animate wheels
        self.object:set_animation_frame_speed(longit_speed * 10)
    else
        --stop wheels
        self.object:set_animation_frame_speed(0)
    end
    
    -- new yaw
	if math.abs(self._rudder_angle)>1 then
        local turn_rate = math.rad(14)
        local yaw_turn = self.dtime * math.rad(self._rudder_angle) * turn_rate *
                demoiselle.sign(longit_speed) * math.abs(longit_speed/2)
		newyaw = yaw + yaw_turn
	end

    --roll adjust
    ---------------------------------
    local delta = 0.002
    if is_flying then
        local roll_reference = newyaw
        local sdir = minetest.yaw_to_dir(roll_reference)
        local snormal = {x=sdir.z,y=0,z=-sdir.x}	-- rightside, dot is negative
        local prsr = demoiselle.dot(snormal,nhdir)
        local rollfactor = -90
        local roll_rate = math.rad(15)
        newroll = (prsr*math.rad(rollfactor)) * (later_speed * roll_rate) * demoiselle.sign(longit_speed)
        --minetest.chat_send_all('newroll: '.. newroll)
    else
        delta = 0.2
        if roll > 0 then
            newroll = roll - delta
            if newroll < 0 then newroll = 0 end
        end
        if roll < 0 then
            newroll = roll + delta
            if newroll > 0 then newroll = 0 end
        end
    end

    ---------------------------------
    -- end roll

	if not is_attached then
        -- for some engine error the player can be detached from the machine, so lets set him attached again
        demoiselle.checkattachBug(self)
    end

    local pilot = player
    if self._command_is_given and passenger then
        pilot = passenger
    else
        self._command_is_given = false
    end

    ------------------------------------------------------
    --accell calculation block
    ------------------------------------------------------
    if is_attached or passenger then
        accel, stop = demoiselle.control(self, self.dtime, hull_direction,
            longit_speed, longit_drag, later_speed, later_drag, accel, pilot, is_flying)
    end

    --end accell

    if accel == nil then accel = {x=0,y=0,z=0} end

    --lift calculation
    accel.y = accel_y --accel.y

    --lets apply some bob in water
	if self.isinliquid then
        local bob = demoiselle.minmax(demoiselle.dot(accel,hull_direction),0.4)	-- vertical bobbing
        accel.y = accel.y + bob
        local max_pitch = 6
        local h_vel_compensation = (((longit_speed * 4) * 100)/max_pitch)/100
        if h_vel_compensation < 0 then h_vel_compensation = 0 end
        if h_vel_compensation > max_pitch then h_vel_compensation = max_pitch end
        newpitch = newpitch + (velocity.y * math.rad(max_pitch - h_vel_compensation))
    end

    local new_accel = accel
    if longit_speed > 1.5 then
        
        new_accel = demoiselle.getLiftAccel(self, velocity, new_accel, longit_speed, roll, curr_pos)
    end
    -- end lift

    if stop ~= true then
        self.object:set_pos(curr_pos)
        self.object:set_velocity(velocity)
        self._last_accell = new_accel
        self.object:set_acceleration(new_accel)
    elseif stop == true then
        self.object:set_velocity({x=0,y=0,z=0})
    end
    ------------------------------------------------------
    -- end accell
    ------------------------------------------------------

    --self.object:get_luaentity() --hack way to fix jitter on climb

    --adjust climb indicator
    local climb_rate = velocity.y * 1.5
    if climb_rate > 5 then climb_rate = 5 end
    if climb_rate < -5 then
        climb_rate = -5
    end

    --is an stall, force a recover
    if self._angle_of_attack > 5 and climb_rate < -3 then
        self._elevator_angle = 0
        self._angle_of_attack = -1
        newpitch = math.rad(self._angle_of_attack)
    end

    --minetest.chat_send_all('rate '.. climb_rate)
    local climb_angle = demoiselle.get_gauge_angle(climb_rate)

    local indicated_speed = longit_speed
    if indicated_speed < 0 then indicated_speed = 0 end
    local speed_angle = demoiselle.get_gauge_angle(indicated_speed, -45)
    --adjust power indicator
    local power_indicator_angle = demoiselle.get_gauge_angle(self._power_lever/10) + 90
    local energy_indicator_angle = (demoiselle.get_gauge_angle((DEMOISELLE_MAX_FUEL - self._energy)*2)) - 90

    if is_attached then
        if self._show_hud then
            demoiselle.update_hud(player, climb_angle, speed_angle, power_indicator_angle, energy_indicator_angle)
        else
            demoiselle.remove_hud(player)
        end
    end

    --apply rotations
    self.object:set_rotation({x=newpitch,y=newyaw,z=newroll})

    --adjust elevator pitch (3d model)
    self.object:set_bone_position("empenagem", {x=0, y=33.5, z=-0.5}, {x=-self._elevator_angle/2.5, y=0, z=self._rudder_angle/2.5})

    -- calculate energy consumption --
    demoiselle.consumptionCalc(self, accel)

    --test collision
    demoiselle.testImpact(self, velocity, curr_pos)

    --saves last velocity for collision detection (abrupt stop)
    self._last_vel = self.object:get_velocity()
end

