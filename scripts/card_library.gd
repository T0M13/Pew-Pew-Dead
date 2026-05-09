class_name CardLibrary
extends RefCounted

# Modular card registry. To add a card:
#   1. Append a new entry to CARDS with a unique id.
#   2. Add a match arm in apply() that mutates the player.
# Cards are pure data + an apply function so picker UI never knows
# about gameplay details.

const RARITY_COMMON := 0
const RARITY_RARE := 1
const RARITY_LEGENDARY := 2

const CARDS: Array[Dictionary] = [
	{
		"id": &"quick_boots",
		"name": "Quick Boots",
		"desc": "Move speed +18%. Bhop ceiling rises with it.",
		"color": Color(0.4, 0.9, 1.0),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"iron_skin",
		"name": "Iron Skin",
		"desc": "+30 max HP and heal +30.",
		"color": Color(1.0, 0.7, 0.3),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"patch_up",
		"name": "Patch Up",
		"desc": "Heal back to full HP.",
		"color": Color(0.95, 0.45, 0.55),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"hot_loads",
		"name": "Hot Loads",
		"desc": "+1 damage on every shot.",
		"color": Color(0.85, 0.5, 1.0),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"glass_cannon",
		"name": "Glass Cannon",
		"desc": "-25 max HP, +2 damage. High risk, high reward.",
		"color": Color(0.9, 0.3, 0.35),
		"rarity": RARITY_RARE,
	},
	{
		"id": &"long_wind",
		"name": "Long Wind",
		"desc": "+50 max stamina. Bhop longer chains.",
		"color": Color(0.65, 0.85, 0.5),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"quick_recovery",
		"name": "Quick Recovery",
		"desc": "Stamina regenerates 50% faster.",
		"color": Color(0.55, 0.95, 0.85),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"vampire",
		"name": "Vampire",
		"desc": "Heal +3 HP every time a zombie dies near you.",
		"color": Color(0.78, 0.18, 0.32),
		"rarity": RARITY_RARE,
	},
	{
		"id": &"heavy_shot",
		"name": "Heavy Shot",
		"desc": "+1 damage and +25% projectile speed.",
		"color": Color(1.0, 0.55, 0.18),
		"rarity": RARITY_RARE,
	},
	{
		"id": &"berserker",
		"name": "Berserker",
		"desc": "Melee cooldown -35% and melee force +40%.",
		"color": Color(0.95, 0.22, 0.55),
		"rarity": RARITY_RARE,
	},
	{
		"id": &"through_and_through",
		"name": "Through and Through",
		"desc": "Bullets pierce one extra enemy.",
		"color": Color(0.55, 1.0, 0.78),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"trickshot",
		"name": "Trickshot",
		"desc": "Bullets bounce one extra time off walls.",
		"color": Color(0.85, 0.95, 0.55),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"spray_and_pray",
		"name": "Spray and Pray",
		"desc": "Rifle fires 30% faster.",
		"color": Color(0.95, 0.65, 0.32),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"hand_cannon",
		"name": "Hand Cannon",
		"desc": "Pistol charges 25% faster, charged shots hit harder.",
		"color": Color(1.0, 0.85, 0.45),
		"rarity": RARITY_RARE,
	},
	{
		"id": &"scattershot",
		"name": "Scattershot",
		"desc": "Shotgun fires +2 pellets.",
		"color": Color(1.0, 0.55, 0.32),
		"rarity": RARITY_RARE,
	},
	{
		"id": &"choke",
		"name": "Choke",
		"desc": "Shotgun spread tightens 35%.",
		"color": Color(0.62, 0.78, 1.0),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"focused_fire",
		"name": "Focused Fire",
		"desc": "Rifle accuracy improved and damage +20%.",
		"color": Color(0.45, 0.85, 1.0),
		"rarity": RARITY_RARE,
	},
	{
		"id": &"crit_master",
		"name": "Crit Master",
		"desc": "+1 base damage and shotgun damage +25%.",
		"color": Color(1.0, 0.42, 0.42),
		"rarity": RARITY_RARE,
	},
	{
		"id": &"stim_pack",
		"name": "Stim Pack",
		"desc": "Heal +50 HP and stamina +75.",
		"color": Color(0.85, 0.95, 0.6),
		"rarity": RARITY_COMMON,
	},
	{
		"id": &"juggernaut",
		"name": "Juggernaut",
		"desc": "+50 max HP, -10% move speed.",
		"color": Color(0.9, 0.6, 0.25),
		"rarity": RARITY_LEGENDARY,
	},
	{
		"id": &"speed_demon",
		"name": "Speed Demon",
		"desc": "Move speed +25%, stamina costs -25%.",
		"color": Color(0.4, 1.0, 0.85),
		"rarity": RARITY_LEGENDARY,
	},
]

static func get_card(id: StringName) -> Dictionary:
	for c in CARDS:
		if c.id == id:
			return c
	return {}

static func random_offer(count: int = 3, exclude: Array = []) -> Array:
	var pool: Array = []
	for c in CARDS:
		if not exclude.has(c.id):
			pool.append(c.id)
	pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))

static func apply(player: Node, card_id: StringName) -> void:
	if player == null:
		return
	match card_id:
		&"quick_boots":
			var step: float = 1.15
			player.move_speed *= step
			player.air_speed_cap *= step
			player.air_strafe_wishspeed *= step
		&"iron_skin":
			player.max_health += 30
			player.health = mini(player.max_health, player.health + 30)
			player.health_changed.emit(player.health, player.max_health)
		&"patch_up":
			player.health = player.max_health
			player.health_changed.emit(player.health, player.max_health)
		&"hot_loads":
			player.damage_bonus += 1
		&"glass_cannon":
			player.max_health = maxi(20, player.max_health - 25)
			player.health = mini(player.max_health, player.health)
			player.damage_bonus += 2
			player.health_changed.emit(player.health, player.max_health)
		&"long_wind":
			player.stamina_max += 50.0
			player.stamina = player.stamina_max
			player.stamina_changed.emit(player.stamina, player.stamina_max)
		&"quick_recovery":
			player.stamina_regen *= 1.5
		&"vampire":
			player.lifesteal_per_kill += 3
		&"heavy_shot":
			player.damage_bonus += 1
			player.projectile_speed_bonus += 0.25
		&"berserker":
			player.melee_cooldown *= 0.65
			player.melee_force *= 1.4
		&"through_and_through":
			player.projectile_pierce_bonus += 1
		&"trickshot":
			player.projectile_bounce_bonus += 1
		&"spray_and_pray":
			player.weapon_rifle_rpm *= 1.3
		&"hand_cannon":
			player.max_charge_time *= 0.75
			player.damage_bonus += 1
		&"scattershot":
			player.weapon_shotgun_pellets += 2
		&"choke":
			player.weapon_shotgun_spread_deg *= 0.65
		&"focused_fire":
			player.weapon_rifle_spread_deg *= 0.5
			player.weapon_rifle_damage_mult *= 1.2
		&"crit_master":
			player.damage_bonus += 1
			player.weapon_shotgun_damage_mult *= 1.25
		&"stim_pack":
			player.health = mini(player.max_health, player.health + 50)
			player.stamina = minf(player.stamina_max, player.stamina + 75.0)
			player.health_changed.emit(player.health, player.max_health)
			player.stamina_changed.emit(player.stamina, player.stamina_max)
		&"juggernaut":
			player.max_health += 50
			player.health = mini(player.max_health, player.health + 50)
			player.move_speed *= 0.9
			player.health_changed.emit(player.health, player.max_health)
		&"speed_demon":
			var step: float = 1.25
			player.move_speed *= step
			player.air_speed_cap *= step
			player.air_strafe_wishspeed *= step
			player.stamina_per_jump *= 0.75
