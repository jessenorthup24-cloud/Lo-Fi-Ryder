extends RefCounted
## The season palette. Every world mesh stores a slot index instead of a color; the toon shader looks
## the slot up here, so the whole world changes season smoothly by moving one uniform.

const W := 64
enum {
	GRASS, GRASS_FOREST, SAND, STONE, DIRT, DIRT_DARK, LEAF_A, LEAF_B,
	TRUNK, PINE, FLOWER_A, FLOWER_B, HAY, PLANK, ROOF_RED, WALL,
	WATER, GRASS_SKY, CLOUD, FENCE, BUSH, ROCK_DARK, PATH, PINE_CAP,
	ICE, ROOF_BLUE, STONE_SIDE, SAND_SIDE, TUFT, CORAL, PUMPKIN, METAL,
	CROP, SOIL, ROOF_GREEN, WALL_PINK, WALL_BLUE, COBBLE, ROCK, SNOWCAP,
	LILY, REED, WOOD_DARK, FRUIT, CANVAS, MOSS, BLOSSOM, PEBBLE,
	RUST, CONCRETE, IVY, ASPHALT_DK, RED_SAND, RED_ROCK,
}

const SEASON_NAMES := ["Spring", "Summer", "Autumn", "Winter"]

# slot: [spring, summer, autumn, winter]
const COLORS := {
	GRASS: ["9ad96b", "86cc5c", "d6b562", "f1f5f8"],
	GRASS_FOREST: ["74c46a", "62b35c", "c99a4c", "e9f0f5"],
	SAND: ["f4dca2", "f6d68e", "eccd94", "ece7df"],
	STONE: ["d3cdc4", "d8d0c4", "cfc5b8", "dfe3e8"],
	DIRT: ["b9835a", "b27b52", "a46f4a", "a07a63"],
	DIRT_DARK: ["8e6650", "88604a", "7f5946", "7d6a60"],
	LEAF_A: ["9ede6c", "62b94f", "f08b3a", "eef3f7"],
	LEAF_B: ["f7b9cb", "55a94b", "e05d3f", "e4ecf1"],
	TRUNK: ["94603f", "8f5b3b", "865436", "7f5a45"],
	PINE: ["47a062", "3e9058", "3f8a5b", "4b8670"],
	FLOWER_A: ["ff93b5", "ff7aa0", "e98063", "e8eef2"],
	FLOWER_B: ["ffdd66", "ffd246", "f6a95e", "eef2f5"],
	HAY: ["eccb6a", "f2cb5c", "deaa46", "ece2c8"],
	PLANK: ["cf9663", "cc9160", "c38757", "c79a78"],
	ROOF_RED: ["c0705f", "bd6a58", "b0614c", "eef0f3"],
	WALL: ["e3d8c6", "e6dac6", "dccfba", "eee9e2"],
	WATER: ["78d0ec", "5ec3ea", "66aeca", "b9def0"],
	GRASS_SKY: ["b2eaa8", "9fe39a", "f0bfa8", "f4f7fc"],
	CLOUD: ["ffffff", "ffffff", "fff7f0", "f7fbff"],
	FENCE: ["d9cfc0", "dbd0bf", "d0c3b0", "ebe7e0"],
	BUSH: ["79c862", "63b552", "d1783e", "e6edf2"],
	ROCK_DARK: ["9a9187", "978c80", "8f8378", "a3a2a6"],
	PATH: ["94918c", "97928b", "8f8a83", "c9ccd1"],
	PINE_CAP: ["47a062", "3e9058", "3f8a5b", "fbfdff"],
	ICE: ["d6f3fd", "d6f3fd", "d6f3fd", "cdeefc"],
	ROOF_BLUE: ["7e93b0", "7890ae", "73879f", "eef0f3"],
	STONE_SIDE: ["c2b2d6", "bcabd2", "c7a9c2", "c9c2dc"],
	SAND_SIDE: ["dfae7c", "dba873", "d29f6e", "cfae94"],
	TUFT: ["7fca5c", "6dba4f", "b98f45", "e3eaf0"],
	CORAL: ["ff9478", "ff8a6b", "f0805f", "f2b3a6"],
	PUMPKIN: ["f6b44a", "f4a43a", "f08a24", "f2c29a"],
	METAL: ["9c8f86", "9a8b80", "958479", "b2b4ba"],
	CROP: ["a9d96c", "ecc95f", "c99a50", "eef2f5"],
	SOIL: ["8f6447", "966a4c", "7f573f", "dde1e6"],
	ROOF_GREEN: ["7ea58b", "76a084", "6f8f78", "eef0f3"],
	WALL_PINK: ["dcc3bc", "dec2b9", "d4b8ad", "eee6e2"],
	WALL_BLUE: ["c3cdd8", "c0cbd8", "bcc4cf", "e4e8ee"],
	COBBLE: ["aaa39a", "aea69c", "a39a8f", "d3d6da"],
	ROCK: ["a69d94", "a89e93", "9e9389", "b8b6bb"],
	SNOWCAP: ["f6f8fb", "f6f8fb", "f6f8fb", "ffffff"],
	LILY: ["6fc35c", "5fb34f", "a8a04a", "bcd8e6"],
	REED: ["93c45f", "82b450", "c4a050", "dfe6ea"],
	WOOD_DARK: ["7a5236", "7a5236", "73502f", "6f5444"],
	FRUIT: ["fff0f5", "e8473f", "f08a24", "e9eef2"],
	CANVAS: ["f2e6cf", "f4e8d0", "eadcc2", "f2eee8"],
	MOSS: ["7cb862", "6aa858", "9a9a4c", "dfe8ec"],
	BLOSSOM: ["ffc2d4", "fff1a8", "f6a65e", "eef2f6"],
	PEBBLE: ["bdb4aa", "c2b8ac", "b3a89c", "d5d8dd"],
	RUST: ["b0643e", "b45f38", "a85532", "b98c7c"],
	CONCRETE: ["b8b2a8", "bcb5aa", "b1a99e", "d9dbe0"],
	IVY: ["5cb04a", "4ea242", "a0903c", "cbd8d1"],
	ASPHALT_DK: ["5f5c59", "625e5a", "5b5752", "a9adb3"],
	RED_SAND: ["e49c62", "e7995c", "dc8f56", "ead9cf"],
	RED_ROCK: ["c4653c", "c86239", "ba5b36", "d6beb3"],
}

static func make_texture() -> ImageTexture:
	var img := Image.create(W, 4, false, Image.FORMAT_RGBA8)
	for slot in COLORS:
		var row: Array = COLORS[slot]
		for s in 4:
			img.set_pixel(slot, s, Color(row[s]))
	return ImageTexture.create_from_image(img)

## The sRGB color of a slot in a season (for UI and particles that don't use the shader).
static func color(slot: int, season: float) -> Color:
	var row: Array = COLORS[slot]
	var s := fposmod(season, 4.0)
	var a := int(floor(s))
	var b := (a + 1) % 4
	var f := smoothstep(0.6, 1.0, s - a)
	return Color(row[a]).lerp(Color(row[b]), f)
