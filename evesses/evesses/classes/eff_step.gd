# ev_effect_step.gd
class_name EvEffectStep
extends RefCounted

enum Mode {
	AND,                # Simultaneous. B happens even if A fails.
	AND_THEN,           # Sequential. B happens only if A succeeds.
	AND_IF_YOU_DO,      # Simultaneous. B happens only if A succeeds.
	AND_THEN_IF_YOU_DO  # Sequential. B happens only if A succeeds.
}

var action: Callable # func(world, context) -> Result
var mode: Mode = Mode.AND

func _init(_action: Callable, _mode: Mode = Mode.AND):
	action = _action
	mode = _mode
