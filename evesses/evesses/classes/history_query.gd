# ev_history_query.gd
class_name EvHistoryQuery
extends RefCounted

var _data: Array[Dictionary]

func _init(history_data: Array[Dictionary]):
	_data = history_data

## Filter by the event tag (e.g., "damage_taken", "card_drawn")
func with_tag(tag: String) -> EvHistoryQuery:
	_data = _data.filter(func(e): return e.tag == tag)
	return self

## Filter by the node that caused or owns the event
func from_source(source: Node) -> EvHistoryQuery:
	var id = source.get_instance_id()
	_data = _data.filter(func(e): return e.source_id == id)
	return self

## Filter by a specific scope (e.g., "turn": 5)
func in_scope(scope_key: String, value: Variant) -> EvHistoryQuery:
	_data = _data.filter(func(e): 
		return e.scopes.get(scope_key) == value
	)
	return self

## Check if any events match the criteria
func exists() -> bool:
	return _data.size() > 0

## Get the count of matching events
func count() -> int:
	return _data.size()

## Access the raw data if needed
func get_results() -> Array[Dictionary]:
	return _data
