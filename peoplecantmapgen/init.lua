-- peoplecantmapgen - Generate flats randomly

local flat_path = minetest.get_modpath("peoplecantmapgen") .. "/schems/flat.mts"

minetest.register_on_generated(function(minp, maxp, seed)
	if maxp.y < 2 and minp.y > 0 then
		-- Only generate this stuff around the y=0 position
		return
	end

	local rand = PseudoRandom(seed + 1234321)

	if rand:next(0, 100) < 50 then
		-- Skip the half of all generated chunks
		return
	end

	-- Convert some nodes into content IDs to use in the VoxelManipulator
	local c_air = minetest.get_content_id("air")
	local c_grass = minetest.get_content_id("default:dirt_with_grass")

	-- Load all the mapgen stuff
	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	-- Array that contains all content IDs of this chunk
	local data = vm:get_data()

	-- Make a random position
	local random_pos = {
		-- x,z: Do not generate on borders
		x = rand:next(minp.x + 5, maxp.x - 5),
		-- y: Dummy value
		y = -1,
		z = rand:next(minp.z + 5, maxp.z - 5)
	}

	-- Searching the ground position

	local found = false
	local last = -1 -- Last content ID, -1 does not exist

	-- From top->down start at y=30
	for y = 30, 0, -1 do
		random_pos.y = y
		-- Get the content ID of the position in random_pos
		last = data[area:index(random_pos.x, random_pos.y, random_pos.z)]
		if last ~= c_air then
			-- Found something solid, exit the loop
			found = true
			break
		end
	end

	if found and last == c_grass then
		-- Found grassy ground, place our flat
		minetest.place_schematic(
			random_pos,
			flat_path,
			"random", -- Random rotation
			nil, -- No replacements
			true -- Forced placement
		)
	end
end)