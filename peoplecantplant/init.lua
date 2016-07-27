-- peoplecantplant - Plant saplings when touching the ground
-- Contains code fragments from builtin/game/item_entity.lua


-- Function that gets called when the builtin item stops
function builtin_item_stopped(self, pos_below, node)
	if minetest.get_item_group(node.name, "soil") == 0 then
		return -- Not soil
	end

	local stack = ItemStack(self.itemstring)
	if stack:get_count() > 1 then
		return -- Obviously dropped by someone (more than 1 item on the stack)
	end

	local item = stack:get_name()
	if minetest.get_item_group(item, "sapling") == 0 then
		return -- It is not a sapling
	end

	if minetest.is_protected(pos_below, ":nobody") then
		return -- The area is protected by someone
	end

	if minetest.find_node_near(pos_below, 3, {"group:sapling", "group:tree"}) then
		return -- There's another tree around, prevent jungle
	end

	-- Using 'pos = pos_below' would not allow us to modify the tables seperately,
	-- thus make a copy of it with vector.new
	local pos = vector.new(pos_below)
	pos.y = pos.y + 1

	if minetest.get_node(pos).name ~= "air" then
		return
	end
	minetest.set_node(pos, {name = item})
	self.itemstring = ""
	self.object:remove()
	return true -- Success!
end


-- Lifespan of an entity, default it to 900 on fail
local time_to_live = tonumber(minetest.setting_get("item_entity_ttl")) or 900

-- Overwrite "on_step" in the entity that's used for dropped items
minetest.registered_entities["__builtin:item"].on_step = function(self, dtime)
	self.age = self.age + dtime
	if time_to_live > 0 and self.age > time_to_live then
		-- Item expired, remove it
		self.itemstring = ""
		self.object:remove()
		return
	end

	local p = self.object:getpos()
	p.y = p.y - 0.5
	local node = minetest.get_node(p)
	local def = minetest.registered_nodes[node.name]
	-- Ignore is walkable, so let it stop until the stuff below loaded
	local entity_fall = (def and not def.walkable)

	if self.physical_state == entity_fall then
		return -- State didn't change, don't do anything
	end

	-- Different to previous state - resetting the velocity doesn't hurt anything
	self.object:setvelocity({x=0, y=0, z=0})
	if entity_fall then
		-- Entity is falling: downwards acceleration of earth
		self.object:setacceleration({x=0, y=-9.81, z=0})
	else
		-- Entity stopped, call our magic planting function
		local success = builtin_item_stopped(self, vector.round(p), node)
		if success then
			return -- The entity doesn't exist anymore when our function was successful
		end

		-- Code from the original __builtin:item, get surrounding objects
		local own_stack = ItemStack(self.itemstring)
		for _, object in ipairs(minetest.get_objects_inside_radius(p, 0.8)) do
			local obj = object:get_luaentity()
			if obj and obj.name == "__builtin:item"
					and obj.physical_state == false then
				-- Try to merge the items around with this one
				if self:try_merge_with(own_stack, object, obj) then
					return -- Item was removed/replaced
				end
			end
		end
		self.object:setacceleration({x=0, y=0, z=0})
	end

	self.physical_state = entity_fall
	self.object:set_properties({
		physical = entity_fall
	})
end