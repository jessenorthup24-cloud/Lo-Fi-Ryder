extends RefCounted
## The season palette. Every world mesh stores a slot index instead of a color; the toon shader looks
## the slot up here, so the whole world changes season smoothly by moving one uniform.

const W := 32
enum {
	GRASS, GRASS_FOREST, SAND, STONE, DIRT, DIRT_DARK, LEAF_A, LEAF_B,
	TRUNK, PINE, FLOWER_A, FLOWER_B, HAY, PLANK, ROOF_RED, WALL,
	WATER, GRASS_SKY, CLOUD, FENCE, BUSH, ROCK_DARK, PATH, PINE_CAP,
	ICE, ROOF_BLUE, STONE_SIDE, SAND_SIDE, TUFT, CORAL, PUMPKIN, METAL,
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
	ROOF_RED: ["e8665a", "e85c4d", "d9573f", "f3f5f8"],
	WALL: ["fff1dc", "fff0d8", "fbe8cf", "f7f0e6"],
	WATER: ["78d0ec", "5ec3ea", "66aeca", "b9def0"],
	GRASS_SKY: ["b2eaa8", "9fe39a", "f0bfa8", "f4f7fc"],
	CLOUD: ["ffffff", "ffffff", "fff7f0", "f7fbff"],
	FENCE: ["fbf1e2", "fdf3e4", "f3e4cf", "f7f3ec"],
	BUSH: ["79c862", "63b552", "d1783e", "e6edf2"],
	ROCK_DARK: ["9a9187", "978c80", "8f8378", "a3a2a6"],
	PATH: ["e2c08d", "e4bf86", "efd9b4", "dcd6ce"],
	PINE_CAP: ["47a062", "3e9058", "3f8a5b", "fbfdff"],
	ICE: ["d6f3fd", "d6f3fd", "d6f3fd", "cdeefc"],
	ROOF_BLUE: ["6797dd", "5d8fda", "5f86c4", "f3f5f8"],
	STONE_SIDE: ["c2b2d6", "bcabd2", "c7a9c2", "c9c2dc"],
	SAND_SIDE: ["dfae7c", "dba873", "d29f6e", "cfae94"],
	TUFT: ["7fca5c", "6dba4f", "b98f45", "e3eaf0"],
	CORAL: ["ff9478", "ff8a6b", "f0805f", "f2b3a6"],
	PUMPKIN: ["f6b44a", "f4a43a", "f08a24", "f2c29a"],
	METAL: ["a6afb9", "a3acb6", "a0a8b0", "b8c0c9"],
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
