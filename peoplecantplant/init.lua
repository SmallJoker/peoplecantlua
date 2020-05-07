-- peoplecantplant - Plant saplings when they touch the ground


-- Function that gets called when the builtin item stops
function builtin_item_stopped(self)
	local stack = ItemStack(self.itemstring)
	if stack:get_count() > 1 then
		return -- Obviously dropped by someone (more than 1 item on the stack)
	end

	local item = stack:get_name()
	if minetest.get_item_group(item, "sapling") == 0 then
		return -- It is not a sapling
	end

	local pos = vector.round(self.object:get_pos())
	local pos_below = vector.new(pos)
	pos_below.y = pos_below.y - 1

	if minetest.is_protected(pos, ":nobody") then
		return -- The area is protected by someone
	end

	local node_below = minetest.get_node(pos_below)
	if minetest.get_item_group(node_below.name, "soil") == 0 then
		return -- Not soil
	end

	if minetest.find_node_near(pos_below, 3, {"group:sapling", "group:tree"}) then
		return -- There's another tree around, prevent jungle
	end

	local node = minetest.get_node(pos).name
	-- Get node definition to decide whether to replace or not
	-- fallback to empty table when it's an unknown node
	local nodedef = minetest.registered_nodes[node] or {}
	if not nodedef.buildable_to then
		return
	end
	minetest.set_node(pos, {name = item})
	self.itemstring = ""
	self.object:remove()
end


-- Overwrite "on_step" in the entity that's used for dropped items
local entity_def = minetest.registered_entities["__builtin:item"]
local old_step = entity_def.on_step
entity_def.on_step = function(self, dtime, ...)
	local old_acc = self.object:get_acceleration()
	old_step(self, dtime, ...)

	if self.itemstring == "" or not self.object:get_pos() then
		return -- Item is removed
	end
	if vector.equals(old_acc, {x=0, y=0, z=0}) then
		return -- No motion change
	end

	-- Acceleration defines in this case whether it's moving or not
	local new_acc = self.object:get_acceleration()
	if vector.equals(new_acc, {x=0, y=0, z=0}) then
		-- Not moving: Try to place on node below
		builtin_item_stopped(self)
	end
end