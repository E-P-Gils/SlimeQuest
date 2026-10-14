extends RefCounted

enum Intent { WATCH, PRESS, RETREAT, FLANK }


static func hesitate_time() -> float:
	return randf_range(0.18, 0.4)


static func watch_time(did_hit: bool) -> float:
	if did_hit:
		return randf_range(0.35, 0.65)
	return randf_range(0.18, 0.4)


static func after_attack(did_hit: bool) -> int:
	var roll := randf()
	if did_hit:
		if roll < 0.12:
			return Intent.WATCH
		if roll < 0.52:
			return Intent.PRESS
		if roll < 0.78:
			return Intent.FLANK
		return Intent.RETREAT
	if roll < 0.08:
		return Intent.WATCH
	if roll < 0.58:
		return Intent.PRESS
	if roll < 0.84:
		return Intent.FLANK
	return Intent.RETREAT


static func retreat_x(from_x: float, away_dir: int) -> float:
	var dir := away_dir if away_dir != 0 else (1 if randf() < 0.5 else -1)
	return from_x + float(dir) * randf_range(28.0, 58.0)


static func flank_x(player_x: float, self_x: float) -> float:
	var side := 1 if self_x >= player_x else -1
	if randf() < 0.45:
		side = -side
	return player_x + float(side) * randf_range(36.0, 72.0)
