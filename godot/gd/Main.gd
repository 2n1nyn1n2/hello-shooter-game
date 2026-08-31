extends Node3D
class_name Main

# -- MESHES ---
const PLAYER_MODEL_PATH = "res://gltf/Characters/Character_Soldier.gltf"
const BOT_MODEL_PATH = "res://gltf/Characters/Character_Enemy.gltf"

# --- GAME CONFIGURATION ---
const TOTAL_BOTS: int = 5
const MAP_SIZE: float = 120.0
const PLAYER_SPEED: float = 8.0
const BOT_SPEED: float = 4.0
const FIRE_RATE: float = 0.15
const DAMAGE: float = 25.0
const BULLET_SPEED: float = 80.0
const HEALTH_PICKUP_HEAL: float = 35.0
const MAX_HEALTH_PICKUPS: int = 12

# --- AUTO-AIM CONFIGURATION ---
const WIDE_MAX_DISTANCE: float = 10.0
const LONG_MAX_DISTANCE: float = 40.0

const WIDE_MAX_ANGLE_DEG: float = 20.0
const LONG_MAX_ANGLE_DEG: float = 10.0

# --- GAME STATE ---
var player: CharacterBody3D
var player_mesh: MeshInstance3D
var camera: Camera3D
var camera_pivot: Node3D
var player_health: float = 100.0
var alive_count: int = TOTAL_BOTS + 1
var can_shoot: bool = true
var is_game_over: bool = false
var bots: Array = []
var bullets: Array = []
var health_pickups: Array = []
var pickup_spawn_timer: float = 0.0
var auto_aim_cone_mesh: MeshInstance3D

# Safe Zone
var zone_mesh: MeshInstance3D
var zone_radius: float = MAP_SIZE / 1.5
var min_zone_radius: float = 5.0
var zone_shrink_rate: float = 1.5

# UI Elements
var hud_label: Label
var reticle: Control
var minimap_control: Control

var wide_cone_mesh: Mesh
var long_cone_mesh: Mesh
var auto_aim_area: Area3D
var auto_aim_mesh_inst: MeshInstance3D
var auto_aim_col_shape: CollisionShape3D

# Custom Shader for Health Fill
var health_shader: Shader


func _ready() -> void:
	create_health_shader()
	setup_environment()
	setup_map()
	setup_safe_zone()
	setup_player()
	spawn_bots()
	setup_health_pickups()
	setup_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	wide_cone_mesh = _create_cone_mesh(WIDE_MAX_DISTANCE, WIDE_MAX_ANGLE_DEG)
	long_cone_mesh = _create_cone_mesh(LONG_MAX_DISTANCE, LONG_MAX_ANGLE_DEG)


func _process(delta: float) -> void:
	if is_game_over:
		return

	update_safe_zone(delta)
	update_hud()
	process_shooting()
	process_bullets(delta)
	process_bots(delta)
	process_pickups(delta)
	if is_instance_valid(minimap_control):
		minimap_control.queue_redraw()


# --- SHADER CREATION ---
func create_health_shader() -> void:
	health_shader = Shader.new()
	health_shader.code = """
	shader_type spatial;
	render_mode blend_mix, depth_draw_opaque;

	uniform vec4 base_color : source_color = vec4(0.1, 0.8, 0.2, 0.4);
	uniform float health_ratio : hint_range(0.0, 1.0) = 1.0;

	varying float model_y;

	void vertex() {
		model_y = VERTEX.y;
	}

	void fragment() {
		float normalized_y = (model_y + 1.2) / 2.4;
		if (normalized_y > health_ratio) {
			ALBEDO = vec3(0.0);
			ALPHA = 0.05;
		} else {
			ALBEDO = base_color.rgb;
			ALPHA = 0.35;
		}
	}
	"""


# --- 1. ENVIRONMENT & MAP GENERATION ---
func setup_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.6, 0.9)
	world_env.environment = env
	add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.shadow_enabled = true
	add_child(light)


func setup_map() -> void:
	var floor_body := StaticBody3D.new()
	var floor_mesh := MeshInstance3D.new()
	var plane_shape := PlaneMesh.new()
	plane_shape.size = Vector2(MAP_SIZE * 2, MAP_SIZE * 2)

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.2, 0.5, 0.2)
	plane_shape.material = floor_mat
	floor_mesh.mesh = plane_shape

	var floor_col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(MAP_SIZE * 2, 0.1, MAP_SIZE * 2)
	floor_col.shape = box_shape

	floor_body.add_child(floor_mesh)
	floor_body.add_child(floor_col)
	add_child(floor_body)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(25):
		var box_body := StaticBody3D.new()
		var box_m := MeshInstance3D.new()
		var box_p := BoxMesh.new()
		var box_size := Vector3(rng.randf_range(2, 5), rng.randf_range(2, 6), rng.randf_range(2, 5))
		box_p.size = box_size

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.4, 0.2)
		box_p.material = mat
		box_m.mesh = box_p

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box_size
		col.shape = shape

		box_body.position = Vector3(
			rng.randf_range(-MAP_SIZE + 10, MAP_SIZE - 10),
			box_size.y / 2.0,
			rng.randf_range(-MAP_SIZE + 10, MAP_SIZE - 10)
		)

		box_body.add_child(box_m)
		box_body.add_child(col)
		add_child(box_body)


func setup_safe_zone() -> void:
	zone_mesh = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = zone_radius
	cylinder.bottom_radius = zone_radius
	cylinder.height = 30.0

	var zone_mat := StandardMaterial3D.new()
	zone_mat.albedo_color = Color(0.1, 0.4, 1.0, 0.25)
	zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cylinder.material = zone_mat

	zone_mesh.mesh = cylinder
	zone_mesh.position = Vector3(0, 15, 0)
	add_child(zone_mesh)


func update_safe_zone(delta: float) -> void:
	if zone_radius > min_zone_radius:
		zone_radius -= zone_shrink_rate * delta
		var cylinder: CylinderMesh = zone_mesh.mesh
		cylinder.top_radius = zone_radius
		cylinder.bottom_radius = zone_radius

	if (
		player
		and Vector2(player.global_position.x, player.global_position.z).length() > zone_radius
	):
		take_player_damage(10.0 * delta)

	for i in range(bots.size() - 1, -1, -1):
		var bot: CharacterBody3D = bots[i]
		if is_instance_valid(bot):
			var bot_dist := Vector2(bot.global_position.x, bot.global_position.z).length()
			if bot_dist > zone_radius:
				damage_bot(bot, 10.0 * delta)


# --- 2. HEALTH POWER-UPS SYSTEM ---
func setup_health_pickups() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(MAX_HEALTH_PICKUPS):
		spawn_health_pickup(
			Vector3(
				rng.randf_range(-MAP_SIZE + 15, MAP_SIZE - 15),
				0.5,
				rng.randf_range(-MAP_SIZE + 15, MAP_SIZE - 15)
			)
		)


func spawn_health_pickup(pos: Vector3) -> void:
	var pickup := Area3D.new()
	pickup.position = pos

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "PickupMesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.8, 0.8)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 1.0, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 1.0, 0.3)
	mat.emission_energy_multiplier = 2.0
	box.material = mat

	mesh_inst.mesh = box
	mesh_inst.position.y = 0.4
	pickup.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 1.2, 1.2)
	col.shape = shape
	col.position.y = 0.4
	pickup.add_child(col)

	pickup.body_entered.connect(
		func(body: Node3D):
			if not is_instance_valid(pickup) or pickup not in health_pickups:
				return

			if body == player and player_health < 100.0:
				heal_player(HEALTH_PICKUP_HEAL)
				health_pickups.erase(pickup)
				pickup.queue_free()
			elif body.has_meta("is_bot") and body.get_meta("is_bot"):
				var bot_hp: float = body.get_meta("hp")
				if bot_hp < 100.0:
					heal_bot(body, HEALTH_PICKUP_HEAL)
					health_pickups.erase(pickup)
					pickup.queue_free()
	)

	add_child(pickup)
	health_pickups.append(pickup)


func process_pickups(delta: float) -> void:
	for i in range(health_pickups.size() - 1, -1, -1):
		var pickup: Area3D = health_pickups[i]
		if is_instance_valid(pickup):
			var dist := Vector2(pickup.global_position.x, pickup.global_position.z).length()
			if dist > zone_radius:
				health_pickups.remove_at(i)
				pickup.queue_free()
				continue

			pickup.rotate_y(2.0 * delta)

	pickup_spawn_timer += delta
	if pickup_spawn_timer >= 8.0:
		pickup_spawn_timer = 0.0
		if health_pickups.size() < MAX_HEALTH_PICKUPS:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var angle := rng.randf_range(0, TAU)
			var dist := rng.randf_range(0, max(0.0, zone_radius - 5.0))
			spawn_health_pickup(Vector3(cos(angle) * dist, 0.5, sin(angle) * dist))


func heal_player(amount: float) -> void:
	player_health = min(100.0, player_health + amount)
	if is_instance_valid(player_mesh) and player_mesh.mesh and player_mesh.mesh.material:
		var mat: ShaderMaterial = player_mesh.mesh.material
		mat.set_shader_parameter("health_ratio", player_health / 100.0)


func heal_bot(bot: CharacterBody3D, amount: float) -> void:
	var current_hp: float = bot.get_meta("hp")
	var new_hp: float = min(100.0, current_hp + amount)
	bot.set_meta("hp", new_hp)

	var bot_mesh: MeshInstance3D = bot.get_node_or_null("BotMesh")
	if bot_mesh and bot_mesh.mesh and bot_mesh.mesh.material:
		var mat: ShaderMaterial = bot_mesh.mesh.material
		mat.set_shader_parameter("health_ratio", new_hp / 100.0)


func get_nearest_health_pickup(pos: Vector3, max_dist: float) -> Area3D:
	var nearest: Area3D = null
	var min_dist := max_dist
	for pickup in health_pickups:
		if is_instance_valid(pickup):
			var dist := pos.distance_to(pickup.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = pickup
	return nearest


# --- 3. PLAYER CREATION & INPUT HANDLING ---
func setup_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.add_to_group("player")

	var model_scene = load(PLAYER_MODEL_PATH)
	if model_scene:
		var model_node = model_scene.instantiate()
		model_node.rotation.y = PI
		model_node.name = "PlayerModel"
		player.add_child(model_node)

	player_mesh = MeshInstance3D.new()
	var caps := CapsuleMesh.new()
	caps.height = 2.4
	caps.radius = 0.5

	var mat := ShaderMaterial.new()
	mat.shader = health_shader
	mat.set_shader_parameter("base_color", Color(0.1, 0.8, 0.2, 0.4))
	mat.set_shader_parameter("health_ratio", 1.0)
	caps.material = mat

	player_mesh.mesh = caps
	player_mesh.position.y = 1.2
	player.add_child(player_mesh)

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 2.4
	shape.radius = 0.5
	col.shape = shape
	col.position.y = 1.2
	player.add_child(col)

	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0, 1.8, 0)
	player.add_child(camera_pivot)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 0.8, 3.0)
	camera_pivot.add_child(camera)

	player.position = Vector3(0, 0, 0)
	add_child(player)

	auto_aim_cone_mesh = MeshInstance3D.new()

	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color(1.0, 1.0, 0.0, 0.5)
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	auto_aim_cone_mesh.material_override = cone_mat

	# Position slightly above the floor to avoid clipping, parented directly to player
	auto_aim_cone_mesh.position = Vector3(0, 0.05, 0)
	player.add_child(auto_aim_cone_mesh)


func _create_cone_mesh(max_distance: float, max_angle_deg: float) -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments = 16
	var tip = Vector3.ZERO

	var max_angle_rad = deg_to_rad(max_angle_deg)

	for i in range(segments):
		var t1 = float(i) / segments
		var t2 = float(i + 1) / segments

		# Spread the arc symmetrically across the forward (-Z) direction
		var angle1 = -max_angle_rad + (t1 * max_angle_rad * 2.0)
		var angle2 = -max_angle_rad + (t2 * max_angle_rad * 2.0)

		# Build flat on the XZ plane (Y is kept at 0)
		var p1 = Vector3(sin(angle1) * max_distance, 0.0, -cos(angle1) * max_distance)
		var p2 = Vector3(sin(angle2) * max_distance, 0.0, -cos(angle2) * max_distance)

		st.add_vertex(tip)
		st.add_vertex(p2)
		st.add_vertex(p1)

	st.generate_normals()
	return st.commit()


func _unhandled_input(event: InputEvent) -> void:
	if is_game_over:
		if (
			(event is InputEventMouseButton and event.pressed)
			or (event is InputEventScreenTouch and event.pressed)
			or (event is InputEventKey and event.pressed)
		):
			get_tree().reload_current_scene()
		return

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player_health <= 0 or is_game_over:
		return

	var input_dir := Vector2.ZERO
	var look_x := 0.0

	var ui_nodes = get_tree().get_nodes_in_group("joystick_ui")
	for joystick_ui in ui_nodes:
		if joystick_ui and "joystick_slide" in joystick_ui and "joystick_look" in joystick_ui:
			var slide_input = joystick_ui.joystick_slide.output
			var look_input = Vector2(joystick_ui.joystick_look.output.x, 0)

			# W/S for Forward/Backward
			slide_input.y += Input.get_axis("move_backward", "move_forward")

			# A/D for Strafe Left/Right
			slide_input.x += Input.get_axis("move_left", "move_right")

			# Q/E for Looking Left/Right
			look_input.x += Input.get_axis("look_left", "look_right")

			slide_input = slide_input.limit_length(1.0)
			look_input = look_input.limit_length(1.0)

			input_dir = slide_input
			look_x = look_input.x

	# Optional fallback to keyboard if no UI joystick is active
	if input_dir == Vector2.ZERO:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			input_dir.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			input_dir.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			input_dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			input_dir.x += 1
		input_dir = input_dir.normalized()

	# Apply rotation from look joystick
	if look_x != 0.0:
		player.rotate_y(-look_x * 2.0 * delta)

	var direction := (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		player.velocity.x = direction.x * PLAYER_SPEED
		player.velocity.z = direction.z * PLAYER_SPEED
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, PLAYER_SPEED)
		player.velocity.z = move_toward(player.velocity.z, 0, PLAYER_SPEED)

	if not player.is_on_floor():
		player.velocity.y -= 20.0 * delta

	player.move_and_slide()


# --- 4. PROJECTILE SHOOTING SYSTEM ---
func process_shooting() -> void:
	var wants_to_shoot = true

	if wants_to_shoot and can_shoot and player_health > 0 and not is_game_over:
		can_shoot = false
		var muzzle_pos = (
			player.global_position + Vector3(0, 1.4, 0) + (player.global_transform.basis.z * -0.8)
		)

		var target_enemy = get_enemy_in_auto_aim_cone()
		if target_enemy:
			player.look_at(
				Vector3(
					target_enemy.global_position.x,
					player.global_position.y,
					target_enemy.global_position.z
				),
				Vector3.UP
			)
			spawn_bullet(muzzle_pos, target_enemy.global_position + Vector3(0, 1.2, 0), true)
		else:
			spawn_bullet(muzzle_pos, get_aim_target(), true)

		await get_tree().create_timer(FIRE_RATE).timeout
		can_shoot = true


func get_enemy_in_auto_aim_cone() -> CharacterBody3D:
	var ui_nodes = get_tree().get_nodes_in_group("joystick_ui")
	var aim_mode = AutoAim.Mode.MANUAL

	for joystick_ui in ui_nodes:
		if joystick_ui and "current_auto_aim_mode" in joystick_ui:
			aim_mode = joystick_ui.current_auto_aim_mode

	if aim_mode == AutoAim.Mode.MANUAL:
		if auto_aim_cone_mesh:
			auto_aim_cone_mesh.visible = false
		return null

	if auto_aim_cone_mesh:
		auto_aim_cone_mesh.visible = true
		auto_aim_cone_mesh.mesh = (
			wide_cone_mesh if aim_mode == AutoAim.Mode.WIDE else long_cone_mesh
		)

	for bot in bots:
		if not is_instance_valid(bot):
			continue
		var to_bot = bot.global_position - player.global_position
		var dist = to_bot.length()
		var max_dist = WIDE_MAX_DISTANCE if aim_mode == AutoAim.Mode.WIDE else LONG_MAX_DISTANCE

		if dist <= max_dist:
			var forward = -player.global_transform.basis.z
			forward.y = 0
			to_bot.y = 0
			var angle = forward.angle_to(to_bot.normalized())
			var max_angle = (
				deg_to_rad(WIDE_MAX_ANGLE_DEG)
				if aim_mode == AutoAim.Mode.WIDE
				else deg_to_rad(LONG_MAX_ANGLE_DEG)
			)

			if angle <= max_angle:
				return bot

	return null


func is_aiming_aid_active() -> bool:
	var screen_center: Vector2 = get_viewport().size / 2
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_dir := camera.project_ray_normal(screen_center)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.exclude = [player]
	var result := space_state.intersect_ray(query)

	if result and result.has("collider"):
		var collider = result.collider
		if collider.has_meta("is_bot") and collider.get_meta("is_bot"):
			return true

	return false


func get_aim_target() -> Vector3:
	var screen_center: Vector2 = get_viewport().size / 2
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_dir := camera.project_ray_normal(screen_center)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.exclude = [player]
	var result := space_state.intersect_ray(query)

	return result.position if result else (ray_origin + ray_dir * 1000.0)


func spawn_bullet(spawn_pos: Vector3, target_point: Vector3, is_player_bullet: bool) -> void:
	var bullet := Area3D.new()
	bullet.position = spawn_pos

	var bullet_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.05
	cylinder.height = 0.4

	var mat := StandardMaterial3D.new()
	var bullet_color := Color(1.0, 0.8, 0.1) if is_player_bullet else Color(1.0, 0.1, 0.1)
	mat.albedo_color = bullet_color
	mat.emission_enabled = true
	mat.emission = bullet_color
	mat.emission_energy_multiplier = 3.0
	cylinder.material = mat

	bullet_mesh.mesh = cylinder
	bullet_mesh.rotation_degrees.x = 90
	bullet.add_child(bullet_mesh)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.15
	col.shape = shape
	bullet.add_child(col)

	add_child(bullet)

	var shoot_dir := (target_point - spawn_pos).normalized()
	bullet.look_at(target_point, Vector3.UP)

	bullet.set_meta("dir", shoot_dir)
	bullet.set_meta("lifetime", 0.0)
	bullet.set_meta("is_player_bullet", is_player_bullet)

	bullet.body_entered.connect(
		func(body: Node3D):
			if is_player_bullet:
				if body == player:
					return
				if body.has_meta("is_bot") and body.get_meta("is_bot"):
					damage_bot(body, DAMAGE)
			else:
				if body.has_meta("is_bot") and body.get_meta("is_bot"):
					return
				if body == player:
					take_player_damage(10.0)

			bullets.erase(bullet)
			bullet.queue_free()
	)

	bullets.append(bullet)


func process_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bullet: Area3D = bullets[i]
		if not is_instance_valid(bullet):
			bullets.remove_at(i)
			continue

		var dir: Vector3 = bullet.get_meta("dir")
		var lifetime: float = bullet.get_meta("lifetime") + delta
		bullet.set_meta("lifetime", lifetime)

		bullet.position += dir * BULLET_SPEED * delta

		if lifetime > 2.0:
			bullets.remove_at(i)
			bullet.queue_free()


func damage_bot(bot: CharacterBody3D, amount: float) -> void:
	if not bot or not bot.has_meta("hp"):
		return

	var current_hp = bot.get_meta("hp") - amount
	bot.set_meta("hp", current_hp)

	var bot_model = bot.get_node_or_null("BotModel")
	if bot_model:
		var anim_player = _find_animation_player(bot_model)
		if anim_player and anim_player.has_animation("hitreact"):
			anim_player.play("hitreact")

	var bot_mesh: MeshInstance3D = bot.get_node("BotMesh")
	if bot_mesh and bot_mesh.mesh and bot_mesh.mesh.material:
		var mat: ShaderMaterial = bot_mesh.mesh.material
		var health_ratio: float = clamp(current_hp / 100.0, 0.0, 1.0)
		mat.set_shader_parameter("health_ratio", health_ratio)

	if current_hp <= 0.0:
		bots.erase(bot)
		bot.queue_free()
		alive_count -= 1


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null


func take_player_damage(amount: float) -> void:
	player_health -= amount
	if player_health <= 0:
		player_health = 0
		trigger_game_over(false)

	if is_instance_valid(player_mesh) and player_mesh.mesh and player_mesh.mesh.material:
		var mat: ShaderMaterial = player_mesh.mesh.material
		var health_ratio: float = clamp(player_health / 100.0, 0.0, 1.0)
		mat.set_shader_parameter("health_ratio", health_ratio)


func trigger_game_over(victory: bool) -> void:
	is_game_over = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if victory:
		hud_label.text = "BOOYAH! #1 VICTORY!\n[ CLICK / PRESS ANY KEY TO RESTART ]"
	else:
		hud_label.text = "GAME OVER! ELIMINATED\n[ CLICK / PRESS ANY KEY TO RESTART ]"


# --- 5. ENEMY BOTS (AI) ---
func spawn_bots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var bot_scene = load(BOT_MODEL_PATH)

	for i in range(TOTAL_BOTS):
		var bot := CharacterBody3D.new()
		bot.set_meta("is_bot", true)
		bot.set_meta("hp", 100.0)
		bot.set_meta("can_shoot", true)

		if bot_scene:
			var bot_model = bot_scene.instantiate()
			bot_model.rotation.y = PI
			bot_model.name = "BotModel"
			bot.add_child(bot_model)

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "BotMesh"
		var caps := CapsuleMesh.new()
		caps.height = 2.4
		caps.radius = 0.5
		var mat := ShaderMaterial.new()
		mat.shader = health_shader
		mat.set_shader_parameter("base_color", Color(0.9, 0.1, 0.1, 0.4))
		mat.set_shader_parameter("health_ratio", 1.0)
		caps.material = mat
		mesh_inst.mesh = caps
		mesh_inst.position.y = 1.2
		bot.add_child(mesh_inst)

		var col := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.height = 2.4
		shape.radius = 0.5
		col.shape = shape
		col.position.y = 1.2
		bot.add_child(col)

		bot.position = Vector3(
			rng.randf_range(-MAP_SIZE + 15, MAP_SIZE - 15),
			1.0,
			rng.randf_range(-MAP_SIZE + 15, MAP_SIZE - 15)
		)

		add_child(bot)
		bots.append(bot)


func process_bots(delta: float) -> void:
	if not is_instance_valid(player) or player_health <= 0 or is_game_over:
		return

	for bot in bots:
		if not is_instance_valid(bot):
			continue

		var bot_pos: Vector3 = bot.global_position
		var bot_hp: float = bot.get_meta("hp")
		var dist_from_center := Vector2(bot_pos.x, bot_pos.z).length()
		var is_outside_zone := dist_from_center > zone_radius

		var target_pos: Vector3
		var stop_distance: float = 3.0

		var nearest_pickup: Area3D = get_nearest_health_pickup(bot_pos, 40.0)

		if is_outside_zone:
			target_pos = Vector3.ZERO
			stop_distance = 1.0
		elif bot_hp < 70.0 and is_instance_valid(nearest_pickup):
			target_pos = nearest_pickup.global_position
			stop_distance = 0.4
		else:
			target_pos = player.global_position
			stop_distance = 3.0

		var dir := target_pos - bot_pos
		dir.y = 0
		var dist := dir.length()

		if dist > stop_distance:
			var move_dir := dir.normalized()
			bot.velocity.x = move_dir.x * BOT_SPEED
			bot.velocity.z = move_dir.z * BOT_SPEED
			bot.look_at(Vector3(target_pos.x, bot.global_position.y, target_pos.z), Vector3.UP)
		else:
			bot.velocity.x = move_toward(bot.velocity.x, 0, BOT_SPEED)
			bot.velocity.z = move_toward(bot.velocity.z, 0, BOT_SPEED)

		var player_dist := (player.global_position - bot_pos).length()
		if player_dist < 35.0 and bot.get_meta("can_shoot"):
			bot_fire_bullet(bot, player.global_position)

		if not bot.is_on_floor():
			bot.velocity.y -= 20.0 * delta

		bot.move_and_slide()


func bot_fire_bullet(bot: CharacterBody3D, target_pos: Vector3) -> void:
	bot.set_meta("can_shoot", false)

	var spawn_pos := bot.global_position + Vector3(0, 1.5, 0)
	var target_with_offset := target_pos + Vector3(0, 1.0, 0)

	spawn_bullet(spawn_pos, target_with_offset, false)

	await get_tree().create_timer(randf_range(0.8, 1.5)).timeout
	if is_instance_valid(bot):
		bot.set_meta("can_shoot", true)


# --- 6. UI OVERLAY & MINIMAP ---
func setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	reticle = Control.new()
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.size = Vector2(12, 12)
	dot.position = Vector2(-6, -6)
	dot.color = Color.RED
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.add_child(dot)
	canvas.add_child(reticle)

	hud_label = Label.new()
	hud_label.position = Vector2(20, 20)
	hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_label.add_theme_color_override("font_color", Color.WHITE)
	hud_label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(hud_label)

	minimap_control = Control.new()
	minimap_control.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap_control.set_anchor_and_offset(SIDE_LEFT, 1.0, -170)
	minimap_control.set_anchor_and_offset(SIDE_TOP, 0.0, 20)
	minimap_control.set_anchor_and_offset(SIDE_RIGHT, 1.0, -20)
	minimap_control.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 170)
	minimap_control.custom_minimum_size = Vector2(150, 150)
	minimap_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_control.draw.connect(_draw_minimap)
	canvas.add_child(minimap_control)


func _draw_minimap() -> void:
	var size := minimap_control.size
	var center := size / 2.0
	var scale_factor: float = (size.x / 2.0) / MAP_SIZE

	minimap_control.draw_circle(center, size.x / 2.0, Color(0.1, 0.1, 0.15, 0.75))
	minimap_control.draw_arc(center, size.x / 2.0, 0, TAU, 32, Color.WHITE, 2.0)

	var ui_zone_r := zone_radius * scale_factor
	minimap_control.draw_arc(center, ui_zone_r, 0, TAU, 32, Color(0.2, 0.6, 1.0, 0.9), 2.0)

	for pickup in health_pickups:
		if is_instance_valid(pickup):
			var rel_pos := (
				Vector2(pickup.global_position.x, pickup.global_position.z) * scale_factor
			)
			var pickup_ui_pos := center + rel_pos
			if (pickup_ui_pos - center).length() <= (size.x / 2.0):
				minimap_control.draw_circle(pickup_ui_pos, 2.0, Color.LIME_GREEN)

	for bot in bots:
		if is_instance_valid(bot):
			var rel_pos := Vector2(bot.global_position.x, bot.global_position.z) * scale_factor
			var bot_ui_pos := center + rel_pos
			if (bot_ui_pos - center).length() <= (size.x / 2.0):
				minimap_control.draw_circle(bot_ui_pos, 3.5, Color.RED)

	if is_instance_valid(player):
		var p_rel := Vector2(player.global_position.x, player.global_position.z) * scale_factor
		var p_ui_pos := center + p_rel

		if (p_ui_pos - center).length() <= (size.x / 2.0):
			minimap_control.draw_circle(p_ui_pos, 4.0, Color.GREEN)

			var fwd := -player.global_transform.basis.z
			var dir_2d := Vector2(fwd.x, fwd.z).normalized() * 10.0
			minimap_control.draw_line(p_ui_pos, p_ui_pos + dir_2d, Color.LIME_GREEN, 2.0)


func update_hud() -> void:
	if is_game_over:
		return

	if alive_count <= 1:
		trigger_game_over(true)
	else:
		hud_label.text = (
			"HP: %d | ALIVE: %d | ZONE RADIUS: %d"
			% [int(player_health), alive_count, int(zone_radius)]
		)
