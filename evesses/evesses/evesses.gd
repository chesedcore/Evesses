class_name Evesses
extends RefCounted

# --- State ---
var world: EvWorld
var history: Array[Dictionary] = []
var rules: Array[EvRule] = []
var chain_stack: Array[EvChainLink] = []

# --- Timing/Scopes ---
# Format: {"turn": 1, "phase": "main"}
var current_scopes: Dictionary = {} 

# --- Signal for UI/Logging ---
signal event_committed(event_data: Dictionary)

func _init(initial_world: EvWorld):
	world = initial_world

# --- Simulation Logic ---
## Tests if a pipeline of actions is legal without changing the real world.
func simulate(steps: Callable) -> Result:
	var sandbox = world.clone()
	# The 'steps' callable would perform mutations on the sandbox.
	# If the sandbox rules permit it, return Result.ok(), else Result.err()
	return steps.call(sandbox)

# --- The Mutation Engine (The Interceptors) ---
## Passes an effect through all active floodgates/modifiers.
func apply_interceptors(context: EvContext) -> EvContext:
	# Sort rules by priority (e.g., Replacement effects last)
	var active_rules = rules.filter(func(r): return r.is_active(self))
	active_rules.sort_custom(func(a, b): return a.priority < b.priority)
	
	for rule in active_rules:
		context = rule.mutate(context)
		# If a rule returns an Error Result in context, the effect is 'negated'
		if context.result.is_err():
			break
	return context

# --- Chain Management ---
func push_to_chain(link: EvChainLink):
	chain_stack.append(link)

func resolve_chain():
	while not chain_stack.is_empty():
		var link = chain_stack.pop_back() # LIFO
		_execute_link(link)

func _execute_link(link: EvChainLink):
	var context = apply_interceptors(link.context)
	
	# If a rule triggered a replacement
	if context.is_replaced:
		# We effectively "re-run" the execution with the new context
		# This allows for nested replacements (A -> B -> C)
		var new_link = EvChainLink.new(
			context.replacement_context.source,
			context.replacement_context.tags[0],
			context.replacement_context,
			link.steps # Or custom steps provided by the rule
		)
		_execute_link(new_link)
		return
	
	var final_result = link.resolve(self)
	
	# After the whole chain link is finished, we commit it to the log
	var entry = {
		"tag": link.tag,
		"source": link.source,
		"result": final_result,
		"targets": link.context.targets,
		"scopes": current_scopes.duplicate(),
		"timestamp": Time.get_ticks_msec()
	}
	
	history.append(entry)
	event_committed.emit(entry)


# --- Triggers ---

var registered_triggers: Array[EvTrigger] = []

func register_trigger(t: EvTrigger):
	registered_triggers.append(t)

func _on_event_committed(entry: Dictionary):
	var triggered_this_time: Array[EvEffectBuilder] = []
	
	for trigger in registered_triggers:
		if trigger.tag == entry.tag and trigger.condition.call(entry):
			# The trigger is met! Generate the effect builder.
			triggered_this_time.append(trigger.effect_builder.call(entry))
	
	if triggered_this_time.size() > 0:
		_handle_simultaneous_triggers(triggered_this_time)

func _handle_simultaneous_triggers(builders: Array[EvEffectBuilder]):
	# 1. Sort by Priority (or ask the User to sort)
	builders.sort_custom(func(a, b): return a.priority > b.priority)
	
	# 2. Open a new Chain and push them all
	# In YGO, simultaneous triggers all go on the same chain.
	for builder in builders:
		builder.request()

# --- Replacement/"Instead" Checks ---

var is_replaced: bool = false
var replacement_context: EvContext = null

func replace_with(new_ctx: EvContext):
	is_replaced = true
	replacement_context = new_ctx
