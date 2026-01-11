class_name EvTrigger
extends RefCounted

var tag: String                # The history tag to watch (e.g., "card_destroyed")
var condition: Callable        # func(history_entry) -> bool
var effect_builder: Callable   # func(history_entry) -> EvEffectBuilder
var priority: int = 0          # Used for auto-sorting triggers
