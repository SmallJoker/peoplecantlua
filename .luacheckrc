unused_args = false
max_line_length = 100

globals = {
}

read_globals = {
	"core",
	"vector",

	"ItemStack",
	"PseudoRandom",
	"VoxelArea",
}

-- Allow overwrite
files["peoplecantplant/init.lua"] = {
	globals = { "core.registered_entities" },
}
