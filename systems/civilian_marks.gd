extends RefCounted

static func clean(game: PaxGame) -> void:
	if not game:
		return
		
	# 1. Проверяем world_markers в engine
	if "map_markers" in game and typeof(game.map_markers) == TYPE_ARRAY:
		for m in game.map_markers:
			if typeof(m) == TYPE_DICTIONARY:
				clear_mark(m)
				
	# 2. Проверяем world словарь данных
	var w = game.get("world")
	if w and typeof(w) == TYPE_DICTIONARY and w.has("marks") and typeof(w["marks"]) == TYPE_ARRAY:
		for m in w["marks"]:
			if typeof(m) == TYPE_DICTIONARY:
				clear_mark(m)

static func clear_mark(m: Dictionary) -> void:
	var desc: String = (str(m.get("title", "")) + " " + str(m.get("text", "")) + " " + str(m.get("description", "")) + " " + str(m.get("name", ""))).to_lower()
	for spam_word in ["вод", "фильтр", "жкх", "труб", "канализац", "отоплен", "водоканал", "заилив", "теплосет"]:
		if spam_word in desc:
			m["cleared"] = true
			m["hidden"] = true
			m["resolved"] = true
			break
