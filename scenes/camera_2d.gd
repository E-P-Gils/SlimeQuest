extends Camera2D
@onready var tilemap = $"../../TileMap" 
func _ready():
	var used_rect = tilemap.get_used_rect()
	var tile_size = tilemap.tile_set.tile_size
	
	var left   = used_rect.position.x * tile_size.x
	var top    = used_rect.position.y * tile_size.y
	var right  = (used_rect.position.x + used_rect.size.x) * tile_size.x
	var bottom = (used_rect.position.y + used_rect.size.y) * tile_size.y
	
	var cam = self  # if script is on Camera2D
	
	cam.limit_left = left
	cam.limit_top = top
	cam.limit_right = right
	cam.limit_bottom = bottom
