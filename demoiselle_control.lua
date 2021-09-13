--global constants
demoiselle.vector_up = vector.new(0, 1, 0)
demoiselle.ideal_step = 0.02
demoiselle.rudder_limit = 30
demoiselle.elevator_limit = 40

dofile(minetest.get_modpath("demoiselle") .. DIR_DELIM .. "demoiselle_utilities.lua")

function demoiselle.check_node_below(obj)
	local pos_below = obj:get_pos()
	pos_below.y = pos_below.y - 0.1
	local node_below = minetest.get_node(pos_below).name
	local nodedef = minetest.registered_nodes[node_below]
	local touching_ground = not nodedef or -- unknown nodes are solid
			nodedef.walkable or false
	local liquid_below = not touching_ground and nodedef.liquidtype ~= "none"
	return touching_ground, liquid_below
end

function demoiselle.powerAdjust(self,dtime,factor,dir,max_power)
    local max = max_power or 100
    local add_factor = factor
    add_factor = add_factor * (dtime/demoiselle.ideal_step) --adjusting the command speed by dtime
    local power_index = self._power_lever

    if dir == 1 then
        if self._power_lever < max then
            self._power_lever = self._power_lever + add_factor
        end
        if self._power_lever > max then
            self._power_lever = max
        end
    end
    if dir == -1 then
        if self._power_lever > 0 then
            self._power_lever = self._power_lever - add_factor
            if self._power_lever < 0 then self._power_lever = 0 end
        end
        if self._power_lever <= 0 then
            self._power_lever = 0
        end
    end
    if power_index ~= self._power_lever then
        demoiselle.engineSoundPlay(self)
    end

end

function demoiselle.control(self, dtime, hull_direction, longit_speed, longit_drag,
                            later_speed, later_drag, accel, player, is_flying)
    if demoiselle.last_time_command > 1 then demoiselle.last_time_command = 1 end
    --if self.driver_name == nil then return end
    local retval_accel = accel

    local stop = false
    local ctrl = nil

	-- player control
	if player then
		ctrl = player:get_player_control()

        --engine and power control
        if ctrl.aux1 and demoiselle.last_time_command > 0.5 then
            demoiselle.last_time_command = 0
		    if self._engine_running then
			    self._engine_running = false
		        -- sound and animation
                if self.sound_handle then
                    minetest.sound_stop(self.sound_handle)
                    self.sound_handle = nil
                end
		        self.engine:set_animation_frame_speed(0)
                self._power_lever = 0 --zero power
		    elseif self._engine_running == false and self._energy > 0 then
			    self._engine_running = true
	            -- sound and animation
                demoiselle.engineSoundPlay(self)
                self.engine:set_animation_frame_speed(60)
		    end
        end

        self._acceleration = 0
        if self._engine_running then
            --engine acceleration calc
            local engineacc = (self._power_lever * demoiselle.max_engine_acc) / 100;
            self.engine:set_animation_frame_speed(60 + self._power_lever)

            local factor = 1

            --increase power lever
            if ctrl.jump then
                demoiselle.powerAdjust(self, dtime, factor, 1)
            end
            --decrease power lever
            if ctrl.sneak then
                demoiselle.powerAdjust(self, dtime, factor, -1)
                if self._power_lever <= 0 and is_flying == false then
                    --break
                    if longit_speed > 0 then
                        engineacc = -1
                        if (longit_speed + engineacc) < 0 then engineacc = longit_speed * -1 end
                    end
                    if longit_speed < 0 then
                        engineacc = 1
                        if (longit_speed + engineacc) > 0 then engineacc = longit_speed * -1 end
                    end
                    if abs(longit_speed) < 0.1 then
                        stop = true
                    end
                end
            end
            --do not exceed
            local max_speed = 6
            if longit_speed > max_speed then
                engineacc = engineacc - (longit_speed-max_speed)
                if engineacc < 0 then engineacc = 0 end
            end
            self._acceleration = engineacc
        else
	        local paddleacc = 0
	        if longit_speed < 1.0 then
                if ctrl.jump then paddleacc = 0.5 end
            end
	        if longit_speed > -1.0 then
                if ctrl.sneak then paddleacc = -0.5 end
	        end
	        self._acceleration = paddleacc
        end

        local hull_acc = vector.multiply(hull_direction,self._acceleration)
        retval_accel=vector.add(retval_accel,hull_acc)

        --pitch
        local pitch_cmd = 0
        if ctrl.up then pitch_cmd = 1 elseif ctrl.down then pitch_cmd = -1 end
        demoiselle.set_pitch(self, pitch_cmd, dtime)

		-- yaw
        local yaw_cmd = 0
        if ctrl.right then yaw_cmd = 1 elseif ctrl.left then yaw_cmd = -1 end
        demoiselle.set_yaw(self, yaw_cmd, dtime)

        --I'm desperate, center all!
        if ctrl.right and ctrl.left then
            self._elevator_angle = 0
            self._rudder_angle = 0
        end
	end

    if longit_speed > 0 then
        if ctrl then
            if ctrl.right or ctrl.left then
            else
                demoiselle.rudder_auto_correction(self, longit_speed, dtime)
            end
        else
            demoiselle.rudder_auto_correction(self, longit_speed, dtime)
        end
        demoiselle.elevator_auto_correction(self, longit_speed, dtime)
    end

    return retval_accel, stop
end

function demoiselle.set_pitch(self, dir, dtime)
    local pitch_factor = 10
	if dir == -1 then
		self._elevator_angle = math.max(self._elevator_angle-pitch_factor*dtime,-demoiselle.elevator_limit)
	elseif dir == 1 then
        if self._angle_of_attack < 0 then pitch_factor = 1 end --lets reduce the command power to avoid accidents
		self._elevator_angle = math.min(self._elevator_angle+pitch_factor*dtime,demoiselle.elevator_limit)
	end
end

function demoiselle.set_yaw(self, dir, dtime)
    local yaw_factor = 25
	if dir == 1 then
		self._rudder_angle = math.max(self._rudder_angle-yaw_factor*dtime,-demoiselle.rudder_limit)
	elseif dir == -1 then
		self._rudder_angle = math.min(self._rudder_angle+yaw_factor*dtime,demoiselle.rudder_limit)
	end
end

function demoiselle.rudder_auto_correction(self, longit_speed, dtime)
    local factor = 1
    if self._rudder_angle > 0 then factor = -1 end
    local correction = (demoiselle.rudder_limit*(longit_speed/2000)) * factor * (dtime/demoiselle.ideal_step)
    local before_correction = self._rudder_angle
    local new_rudder_angle = self._rudder_angle + correction
    if math.sign(before_correction) ~= math.sign(new_rudder_angle) then
        self._rudder_angle = 0
    else
        self._rudder_angle = new_rudder_angle
    end
end

function demoiselle.elevator_auto_correction(self, longit_speed, dtime)
    local factor = 1
    --if self._elevator_angle > -1.5 then factor = -1 end --here is the "compensator" adjusto to keep it stable
    if self._elevator_angle > 0 then factor = -1 end
    local correction = (demoiselle.elevator_limit*(longit_speed/5000)) * factor * (dtime/demoiselle.ideal_step)
    local before_correction = self._elevator_angle
    local new_elevator_angle = self._elevator_angle + correction
    if math.sign(before_correction) ~= math.sign(new_elevator_angle) then
        self._elevator_angle = 0
    else
        self._elevator_angle = new_elevator_angle
    end
end

function demoiselle.engineSoundPlay(self)
    --sound
    if self.sound_handle then minetest.sound_stop(self.sound_handle) end
    self.sound_handle = minetest.sound_play({name = "demoiselle_engine"},
        {object = self.object, gain = 2.0,
            pitch = 0.5 + ((self._power_lever/100)/2),max_hear_distance = 32,
            loop = true,})
end

function getAdjustFactor(curr_y, desired_y)
    local max_difference = 0.1
    local adjust_factor = 0.5
    local difference = math.abs(curr_y - desired_y)
    if difference > max_difference then difference = max_difference end
    return (difference * adjust_factor) / max_difference
end


