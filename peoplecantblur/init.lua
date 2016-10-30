-- peoplecantblur - Generate flat areas

local HEIGHT_CHECK = 30
local c_air = minetest.get_content_id("air")


-- Function to get the node definition groups to check for a surface node
local function check_surface_content(c_id, cache_c)
	if cache_c[c_id] ~= nil then
		return cache_c[c_id]
	end

	-- Not contain in the table yet
	local name = minetest.get_name_from_content_id(c_id)
	local def = minetest.registered_nodes[name]
	if not (def and def.groups) then
		return false -- Unknown node
	end

	local is_surface_content = def.groups.soil or def.groups.sand or def.groups.stone
	if not is_surface_content then
		for k, v in pairs(minetest.registered_biomes) do
			if v.node_top == name then
				is_surface_content = true
				break
			end
		end
	end
	cache_c[c_id] = (is_surface_content ~= nil)
	return is_surface_content
end

-- Find the ground of a coordinate
local function get_ground(data, area, pos, max_height, cache_c, get_contents)
	local id_cache = {}
	local rel_surface -- Relative height of surface

	-- Find the ground height (check downwards)
	for y = 0, -max_height + 4, -1 do
		local c_id = data[area:index(pos.x, pos.y + y, pos.z)]
		local is_surface_content = check_surface_content(c_id, cache_c)
		id_cache[y] = { c_id, is_surface_content }

		if is_surface_content then
			if y ~= 0 then
				rel_surface = y
			end
			break
		end
	end

	if not rel_surface then
		-- Check upper area
		for y = max_height - 1, 0, -1 do
			local c_id = data[area:index(pos.x, pos.y + y, pos.z)]
			local is_surface_content = check_surface_content(c_id, cache_c)
			id_cache[y] = { c_id, is_surface_content }

			if is_surface_content then
				if y ~= max_height - 1 then
					rel_surface = y
				end
				break
			end
		end
	end

	if not rel_surface then
		-- Can not find ground in the air
		return {}
	end

	if not get_contents then
		return { rel_surface = rel_surface }
	end

	-- Get the ground contents
	local c_contents = {}
	local c_last_good = id_cache[rel_surface][1]

	for y = rel_surface, rel_surface - 4, -1 do
		local c_data = id_cache[y] -- { c_id, is_surface_content }
		if not c_data then
			local c_id = data[area:index(pos.x, pos.y + y, pos.z)]
			local is_surface_content = check_surface_content(c_id, cache_c)
			c_data = { c_id, is_surface_content }
		end

		-- insert: (is_surface_content) ? c_id : c_last_good
		table.insert(c_contents, c_data[2] and c_data[1] or c_last_good)

		if c_data[2] then
			c_last_good = c_data[1]
		end
	end

	-- Stretch the node above if it's air, a liquid, tree etc.
	local c_above
	local c_id = id_cache[rel_surface + 1][1]
	local name = minetest.get_name_from_content_id(c_id)
	local def = minetest.registered_nodes[name]
	if def and (def.drawtype == "normal"
			or def.drawtype == "airlike"
			or def.drawtype == "liquid") then
		c_above = c_id
	end

	return {
		rel_surface = rel_surface,
		c_contents = c_contents,
		c_above = (c_above or c_air)
	}
end

local function flatten(ppos, radius)
	-- Flattened area is within radius, we need one more to use the blur function
	local minp = vector.add(ppos, -radius - 1)
	local maxp = vector.add(ppos, radius + 1)
	-- Required to check the ground properly
	minp.y = minp.y - HEIGHT_CHECK
	maxp.y = maxp.y + HEIGHT_CHECK
	local max_height = radius + HEIGHT_CHECK

	local heightmap = {}

	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	local data = vm:get_data()

	-- Lookup table for content ID groups
	local cache_c = {}

	for z = minp.z, maxp.z do
	for x = minp.x, maxp.x do
		local ground = get_ground(
				data,
				area,
				vector.new(x, ppos.y, z),
				max_height,
				cache_c,
				math.abs(x - ppos.x) <= radius and math.abs(z - ppos.z) <= radius
		)
		heightmap[z * 0x10000 + x] = ground
	end
	end

	-- Get the relative height from the heightmap with relative coordinates
	local get_height = function(map, x, z, fallback)
		local info = map[z * 0x10000 + x]
		if info and info.rel_surface then
			return info.rel_surface
		end
		return fallback
	end

	local _dirty_ = false
	local E = 1 -- effect width

	-- Apply blur filter on each position and update the nodes
	for z = minp.z + E, maxp.z - E do
	for x = minp.x + E, maxp.x - E do
		local p_info = heightmap[z * 0x10000 + x]
		local nodes = p_info.c_contents
		local old_h = p_info.rel_surface
		local above = p_info.c_above

		if nodes and #nodes > 0 and old_h then
		--[[
			+----+----+----+
			|  1 |  2 |  1 |   4
			|  2 |  1 |  2 |   5
			|  1 |  2 |  1 |   4
			+----+----+----+   -> 13
		]]
		local h = old_h + (
			  get_height(heightmap, x    , z - E, old_h)
			+ get_height(heightmap, x - E, z    , old_h)
			+ get_height(heightmap, x + E, z    , old_h)
			+ get_height(heightmap, x    , z + E, old_h)
		) * 2 + (
			  get_height(heightmap, x - E, z - E, old_h)
			+ get_height(heightmap, x + E, z - E, old_h)
			+ get_height(heightmap, x - E, z + E, old_h)
			+ get_height(heightmap, x + E, z + E, old_h)
		)

		h = math.floor(h / 13 + 0.5)
		if h ~= old_h then
			-- Height changed -> Change terrain
			local max_y = math.max(h, old_h) + 1
			local min_y = math.min(h, old_h) - 3
			local i = 1
			for y = max_y, min_y, -1 do
				local vi = area:index(x, ppos.y + y, z)
				if y > h then
					if h > old_h then
						data[vi] = c_air
					else
						data[vi] = above
					end
				else
					data[vi] = nodes[math.min(#nodes, i)]
					i = i + 1
				end
				_dirty_ = true
			end
		end
		end
	end
	end

	if not _dirty_ then
		return
	end
	vm:set_data(data)
	vm:write_to_map(data)
	vm:update_liquids()
	vm:update_map()
end


minetest.register_chatcommand("flat", {
	description = "Makes the area around you flatter.",
	privs = {server = true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		local player_pos = vector.round(player:getpos())
		-- Flatten an area of (2 * 7 + 1) ^ 2 square meters
		flatten(player_pos, 7)
		return true, "OK."
	end
})