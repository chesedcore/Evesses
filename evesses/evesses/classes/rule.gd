# ev_rule.gd
class_name EvRule
extends RefCounted

var id: String
var priority: int = 0 # Higher = executes later
var lease_scope: String = "" # e.g., "turn"
var lease_value: Variant # e.g., 1 (The specific turn index)

var condition: Callable # func(context) -> bool
var mutator: Callable   # func(context) -> EvContext

func is_active(engine: Evesses) -> bool:
	if lease_scope == "": return true
	return engine.current_scopes.get(lease_scope) == lease_value

func mutate(context: EvContext) -> EvContext:
	if condition.call(context):
		return mutator.call(context)
	return context
