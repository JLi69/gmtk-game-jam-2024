extends Node2D

@export var get_request: PackedScene
@export var bad_request: PackedScene
@export var download_request: PackedScene

var coins: int = 0 
const SALE_PERCENT_RECOVERED: float = 0.25 #the amount of value recouped when you sell something
var current_tile = Vector2i.ZERO
var is_game_over: bool = false

var alternative: int = 0

# keeps track of the number of backed up requests, if any of these
# exceed a certain threshold then you lose the game
var spawn_counts = {
	"get": 0,
	"return": 0,
	"bad": 0,
	"download": 0,
}

var max_counts = {
	"get": 1024,
	"bad": 128,
	"download": 512,
}

# once a timer runs out, reset it to these times
var reset_times = {
	"get": 3.0,
	"bad": 7.0,
	"download": 7.0,
}

# How fast each timer should speed up
var speed_up = {
	"get": 0.05,
	"bad": 0.07,
	"download": 0.2
}

var timers = {
	"get": 3.0,
	"bad": 180.0,
	"download": 300.0,
}

var input_pipes = []

const tile_atlas_positions = {
	"in": Vector2i(0, 0),
	"out": Vector2i(1,0),
	"splitter": Vector2i(0,1),
	"green_filter": Vector2i(1,1),
	"white_filter": Vector2i(1,2),
	"blue_filter": Vector2i(2,2),
	"server": Vector2i(2,1),
	"deleter": Vector2i(3,1),
	"storage": Vector2i(0,2),
	"merger": Vector2i(3, 2),
	"conveyor": Vector2i(0,3),
	"conveyor_corner": Vector2i(2, 3),
}

var tile_costs = {
	"in": 2000,
	"out": 100,
	"green_filter": 60,
	"white_filter": 60,
	"blue_filter": 60,
	"server": 40,
	"splitter": 30,
	"deleter": 20,
	"storage": 80,
	"merger": 60,
	"conveyor": 1,
	"conveyor_corner": 1,
}

const COST_MULTIPLIER: int = 8

func add_top_tile(id: String, x: int, y: int) -> void:
	var tiledata = $TopTileMapLayer.get_cell_tile_data(Vector2i(x, y))
	if id == "delete":
		if tiledata and len(input_pipes) == 1 and tiledata.get_custom_data("Type") == "input":
			return
		tiledata = $BottomTileMapLayer.get_cell_tile_data(Vector2i(x, y))
		if tiledata and tile_costs.has(tiledata.get_custom_data("Type")):
			var refund = int(tile_costs[tiledata.get_custom_data("Type")] * SALE_PERCENT_RECOVERED)
			if tile_costs[tiledata.get_custom_data("Type")] > 0:
				refund = max(refund, 1)
			add_coins(refund)
		$TopTileMapLayer.erase_cell(Vector2i(x, y))
		$BottomTileMapLayer.erase_cell(Vector2i(x, y))
		var input_pipes_len = len(input_pipes)
		input_pipes.erase(Vector2i(x, y))
		# Check if we erased a pipe
		if len(input_pipes) < input_pipes_len:
			tile_costs["in"] /= COST_MULTIPLIER
		if tiledata:
			$Audio/Destroy.play()
		return
	if tiledata != null:
		return
	tiledata = $BottomTileMapLayer.get_cell_tile_data(Vector2i(x, y))
	if tiledata and tiledata.get_custom_data("Type") != "conveyor" and tiledata.get_custom_data("Type") != "conveyor_corner":
		return
	# replace conveyor belt
	if tiledata and (tiledata.get_custom_data("Type") == "conveyor" or tiledata.get_custom_data("Type") == "conveyor_corner"):
		coins += 1
	if spend_coins(tile_costs[id]):
		$Audio/Place.play()
		if id == "in":
			tile_costs[id] *= COST_MULTIPLIER
			input_pipes.push_back(Vector2i(x, y))
		$BottomTileMapLayer.erase_cell(Vector2i(x, y))
		$BottomTileMapLayer.set_cell(Vector2i(x, y), 0, tile_atlas_positions[id], alternative)
		$TopTileMapLayer.set_cell(Vector2i(x, y), 0, tile_atlas_positions[id], alternative)
	else:
		print("insufficent funds")

func add_bottom_tile(id: String, x: int, y: int) -> void:
	var tiledata = $TopTileMapLayer.get_cell_tile_data(Vector2i(x, y))
	if tiledata != null:
		return
	tiledata = $BottomTileMapLayer.get_cell_tile_data(Vector2i(x, y))
	if tiledata != null:
		return
	if(coins >= tile_costs[id]):
		$Audio/Place.play()
		add_coins(-tile_costs[id])
		$TopTileMapLayer.erase_cell(Vector2i(x, y))
		$BottomTileMapLayer.set_cell(Vector2i(x, y), 0, tile_atlas_positions[id], alternative)
	else:
		print("insufficent funds")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_coins(100) # Makes sure the user starts with 100 coins
	for t in $TopTileMapLayer.get_used_cells_by_id(-1, tile_atlas_positions["in"]):
		input_pipes.push_back(t)
	
func update_timers(dt: float) -> void:
	# iterate through timers to update them
	for id in timers:
		timers[id] -= dt

func spawn() -> void:
	for id in timers:
		if timers[id] <= 0.0:
			if len(input_pipes) == 0:
				continue
			# Chose a random input pipe
			var rand_pipe = input_pipes[randi() % len(input_pipes)]
			var instance
			if id == "get":
				instance = get_request.instantiate()
			elif id == "bad":
				instance = bad_request.instantiate()
			elif id == "download":
				instance = download_request.instantiate()
				
			# Place the request in the world
			instance.position = $TopTileMapLayer.map_to_local(rand_pipe)
			$Requests.add_child(instance)
			timers[id] = reset_times[id]
			reset_times[id] = max(reset_times[id] - speed_up[id], 0.18)  
			spawn_counts[id] += 1

func _unhandled_input(event):
	if is_game_over:
		return
	
	if (event.is_action_pressed("left_click")):
		var pos=$TopTileMapLayer.local_to_map(get_global_mouse_position())
		if ($HUD.get_selected() == "conveyor" or $HUD.get_selected() == "conveyor_corner"):
			add_bottom_tile($HUD.get_selected(), pos[0], pos[1])
		elif ($HUD.get_selected() != ""):
			add_top_tile($HUD.get_selected(), pos[0], pos[1])
	if (event.is_action_pressed("right_click") and !Input.is_action_pressed("reverse_rotation")):
		if $HUD.get_selected() != "" and $HUD.get_selected() != "delete":
			alternative += 1
			$PreviewTileMapLayer.set_cell(current_tile, 0, tile_atlas_positions[$HUD.get_selected()], alternative)
			$PreviewTileMapLayer.fix_invalid_tiles()
			if $PreviewTileMapLayer.get_cell_alternative_tile(current_tile) == -1:
				alternative = 0
				$PreviewTileMapLayer.set_cell(current_tile, 0, tile_atlas_positions[$HUD.get_selected()], alternative)
	elif (event.is_action_pressed("right_click") and Input.is_action_pressed("reverse_rotation")):
		if $HUD.get_selected() != "" and $HUD.get_selected() != "delete":
			alternative -= 1
			$PreviewTileMapLayer.set_cell(current_tile, 0, tile_atlas_positions[$HUD.get_selected()], alternative)
			$PreviewTileMapLayer.fix_invalid_tiles()
			if $PreviewTileMapLayer.get_cell_alternative_tile(current_tile) == -1:
				var atlas_pos = tile_atlas_positions[$HUD.get_selected()]
				var source = $PreviewTileMapLayer.tile_set.get_source(0)
				alternative = source.get_alternative_tiles_count(atlas_pos) - 1
				$PreviewTileMapLayer.set_cell(current_tile, 0, tile_atlas_positions[$HUD.get_selected()], alternative)

func display_preview():
	if current_tile == $PreviewTileMapLayer.local_to_map(get_global_mouse_position()):
		return
	else:
		$PreviewTileMapLayer.erase_cell(current_tile)
		current_tile = $PreviewTileMapLayer.local_to_map(get_global_mouse_position())
		if ($HUD.get_selected() == "delete"):
			$PreviewTileMapLayer.material.set_shader_parameter("remove", true)
			$PreviewTileMapLayer.set_cell(current_tile, 0, Vector2i.ZERO)
		elif ($HUD.get_selected() != ""):
			$PreviewTileMapLayer.material.set_shader_parameter("remove", false)
			$PreviewTileMapLayer.set_cell(current_tile, 0, tile_atlas_positions[$HUD.get_selected()], alternative)

func check_game_over():
	for item in spawn_counts:
		if max_counts.has(item) and max_counts[item]:
			if spawn_counts[item] > max_counts[item]:
				game_over("THE SERVER CRASHED!")
	if coins < 0:
		game_over("YOU WENT BANKRUPT!")

func game_over(msg: String):
	if !is_game_over:
		$Audio/Gameover.play()
	is_game_over = true
	get_tree().paused = true
	$HUD/GameOver.text = msg

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if !get_tree().paused:
		update_timers(delta)
	display_preview()
	spawn()
	$HUD.update_text()
	check_game_over()
	
	if Input.is_action_just_pressed("pause"):
		get_tree().paused = !get_tree().paused

func spend_coins(coinAmt):
	if(coins>=coinAmt):
		coins-=coinAmt
		$HUD.publish_coins(coins)
		return true
	else:
		print("insufficent funds")
		return false

func add_coins(coinAmt):
	coins += coinAmt
	$HUD.publish_coins(coins)
