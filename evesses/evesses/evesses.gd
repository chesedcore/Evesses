class_name Evesses
extends RefCounted

#NOTE!!!! This code uses Result and Option types from Tinne K's addon
#          for proper error handling!!!
#if you intend to implement your own, make sure:
#Result must have: Ok(value), Err(error), is_ok(), is_err(), unwrap(), unwrap_or(), unwrap_err(), and_then(), map(), map_err()
#Option must have: Some(value), None(), is_some(), is_none(), unwrap(), unwrap_or(), and_then(), map()

#region Error Types

class ActivationNegated:
	var reason: String
	func _init(r: String = ""):
		reason = r

class EffectNegated:
	var reason: String
	func _init(r: String = ""):
		reason = r

class ActionForbidden:
	var reason: String
	var floodgate
	func _init(r: String = "", fg = null):
		reason = r
		floodgate = fg

class CostCannotBePaid:
	var reason: String
	func _init(r: String = ""):
		reason = r

class ConstraintViolated:
	var constraint_name: String
	func _init(name: String = ""):
		constraint_name = name

class InfiniteLoopDetected:
	var iterations: int
	func _init(i: int = 0):
		iterations = i

#endregion

#region Core Data Structures

enum Phase {
	REQUEST,
	RESOLUTION,
	COMMIT
}

enum CompoundType {
	AND_THEN,
	AND,
	AND_IF_YOU_DO,
	AND_THEN_IF_YOU_DO
}

class TimingEvent:
	var timing: String
	var layer: int
	var data: Dictionary
	var timestamp: int
	var scope_stack: Array[Dictionary] #array of {scope: String, layer: int}
	
	func _init(t: String, l: int = 1, d: Dictionary = {}):
		timing = t
		layer = l
		data = d
		scope_stack = []

class ActionResult:
	#extended result type that tracks whether action actually did something
	var succeeded: bool #did the action complete successfully?
	var timing_events: Array[TimingEvent] #what timing events were generated?
	
	func _init(s: bool = false, events = []):
		succeeded = s
		timing_events = events if events is Array else [events] if events else []

class Effect:
	var tags: Array[String] = []
	var cost: Callable #func(ctx: Context) -> Result
	var cost_checker: Callable #func(ctx: Context) -> Result, for checking without mutating
	var constraints: Array[Callable] = [] #array of func(ctx: Context) -> Result
	var target: Callable #func(ctx: Context) -> Result (returns selected targets)
	var action: Callable #func(ctx: Context, targets) -> Result
	var compound_actions: Array[Dictionary] = [] #{type: CompoundType, action: Callable}
	var lifetime_node: Node = null
	
	func _init():
		cost = func(_ctx): return Result.Ok(null)
		cost_checker = func(_ctx): return Result.Ok(null)
		target = func(_ctx): return Result.Ok([])
		action = func(_ctx, _targets): return Result.Ok(ActionResult.new(false))
	
	func has_tag(tag: String) -> bool:
		return tags.has(tag)

class Trigger:
	var timing: String
	var layer: int
	var filter: Callable #func(event: TimingEvent) -> bool
	var is_optional: bool
	var effect: Effect
	var lifetime_node: Node = null
	
	func _init(t: String, l: int = 1):
		timing = t
		layer = l
		filter = func(_event): return true
		is_optional = false
		effect = Effect.new()

class Floodgate:
	var phase: Phase
	var layer: int
	var forbid: Callable #func(ctx, effect) -> bool, returns true if forbidden
	var modify: Callable #func(ctx, value) -> Variant, modifies and returns value
	var replace: Callable #func(ctx, action) -> Variant, replaces action
	var lifetime_node: Node = null
	var type: String #"forbid", "modify", or "replace"
	
	func _init():
		phase = Phase.REQUEST
		layer = 0
		type = "none"

#endregion

#region State

var _timing_history: Array[TimingEvent] = []
var _current_scope_stack: Array[Dictionary] = [] #{scope: String, layer: int}
var _constraint_tracker: Dictionary = {} #track once per turn, etc
var _active_floodgates: Array[Floodgate] = []
var _active_triggers: Array[Trigger] = []
var _chain_stack: Array = [] #stack of {effect, targets, ctx} waiting to resolve
var _pending_responses: Array[Trigger] = [] #triggers waiting to activate
var _timestamp: int = 0
var _segoc_sorter: Callable #func(triggers: Array[Trigger]) -> Array[Trigger]
var _floodgate_insertion_order: Dictionary = {} #floodgate -> order_index
var _next_insertion_index: int = 0
var _max_chain_iterations: int = 1000 #safety limit to prevent infinite loops

#endregion

#region Initialization

func _init():
	_segoc_sorter = func(triggers): return triggers #default: no sorting

#endregion

#region Public API

func direct_effect() -> EffectBuilder:
	return EffectBuilder.new(self)

func on_timing(timing: String, layer: int = 1) -> TriggerBuilder:
	return TriggerBuilder.new(self, timing, layer)

func floodgate() -> FloodgateBuilder:
	return FloodgateBuilder.new(self)

func timing(scope: String, layer: int) -> void:
	#enter a new temporal scope
	_current_scope_stack.append({scope = scope, layer = layer})

func end_timing(scope: String) -> void:
	#exit the most recent matching scope
	for i in range(_current_scope_stack.size() - 1, -1, -1):
		if _current_scope_stack[i].scope == scope:
			_current_scope_stack.remove_at(i)
			break

func set_segoc_sorter(sorter: Callable) -> void:
	_segoc_sorter = sorter

func set_max_chain_iterations(max_iterations: int) -> void:
	_max_chain_iterations = max_iterations

func activate_effect(effect: Effect, ctx: Context) -> Result:
	#only does REQUEST phase - adds to chain without resolving
	return _request_phase(effect, ctx)

func get_timing_history() -> Array[TimingEvent]:
	return _timing_history.duplicate()

func clear_constraint_tracker() -> void:
	_constraint_tracker.clear()

func resolve_chain(ctx: Context) -> Result:
	#resolves entire chain in reverse order, processing all triggered responses
	#continues until both chain stack and pending responses are empty
	var iterations = 0
	
	while _chain_stack.size() > 0 or _pending_responses.size() > 0:
		iterations += 1
		if iterations > _max_chain_iterations:
			return Result.Err(InfiniteLoopDetected.new(iterations))
		
		#resolve the current chain stack
		if _chain_stack.size() > 0:
			var result = _resolve_chain_stack()
			if result.is_err():
				return result
		
		#process any triggers that were activated
		if _pending_responses.size() > 0:
			var sorted = _segoc_sorter.call(_pending_responses.duplicate())
			_pending_responses.clear()
			
			for trigger in sorted:
				if trigger.is_optional:
					#TODO: in a real implementation, prompt the player here
					#for now, auto-activate all optionals
					pass
				
				#activate the trigger's effect (adds to chain stack)
				var result = _request_phase(trigger.effect, ctx)
				if result.is_err():
					#this trigger couldn't activate, skip it
					continue
	
	return Result.Ok(null)

#endregion

#region Internal Registration

func _register_trigger(trigger: Trigger) -> void:
	_active_triggers.append(trigger)
	
	if trigger.lifetime_node:
		#connect to both lifetime_expired signal (if exists) and tree_exited
		if trigger.lifetime_node.has_signal("lifetime_expired"):
			trigger.lifetime_node.lifetime_expired.connect(
				func(): _unregister_trigger(trigger),
				CONNECT_ONE_SHOT
			)
		
		#always connect to tree_exited as a fallback
		trigger.lifetime_node.tree_exited.connect(
			func(): _unregister_trigger(trigger),
			CONNECT_ONE_SHOT
		)

func _unregister_trigger(trigger: Trigger) -> void:
	_active_triggers.erase(trigger)

func _register_floodgate(floodgate: Floodgate) -> void:
	_active_floodgates.append(floodgate)
	_floodgate_insertion_order[floodgate] = _next_insertion_index
	_next_insertion_index += 1
	
	#sort by layer, then by insertion order for same layer
	_active_floodgates.sort_custom(func(a, b):
		if a.layer != b.layer:
			return a.layer < b.layer
		return _floodgate_insertion_order[a] < _floodgate_insertion_order[b]
	)
	
	if floodgate.lifetime_node:
		#connect to both lifetime_expired signal (if exists) and tree_exited
		if floodgate.lifetime_node.has_signal("lifetime_expired"):
			floodgate.lifetime_node.lifetime_expired.connect(
				func(): _unregister_floodgate(floodgate),
				CONNECT_ONE_SHOT
			)
		
		#always connect to tree_exited as a fallback
		floodgate.lifetime_node.tree_exited.connect(
			func(): _unregister_floodgate(floodgate),
			CONNECT_ONE_SHOT
		)

func _unregister_floodgate(floodgate: Floodgate) -> void:
	_active_floodgates.erase(floodgate)
	_floodgate_insertion_order.erase(floodgate)

#endregion

#region Three-Phase Pipeline

func _request_phase(effect: Effect, ctx: Context) -> Result:
	#check constraints
	for constraint in effect.constraints:
		if constraint == null:
			push_warning("null constraint in effect")
			continue
		
		var result = constraint.call(ctx)
		if result.is_err():
			return result
	
	#check if activation is forbidden by floodgates
	for floodgate in _active_floodgates:
		if floodgate.phase == Phase.REQUEST and floodgate.type == "forbid":
			if floodgate.forbid == null:
				push_warning("forbid floodgate has null callable")
				continue
			
			if floodgate.forbid.call(ctx, effect):
				return Result.Err(ActionForbidden.new("forbidden by floodgate", floodgate))
	
	#check if cost can be paid (using checker)
	if effect.cost_checker != null:
		var cost_check = effect.cost_checker.call(ctx)
		if cost_check.is_err():
			return cost_check
	
	#pay the cost (this cannot be negated)
	if effect.cost != null:
		var cost_result = effect.cost.call(ctx)
		if cost_result.is_err():
			return cost_result
	
	#select targets
	if effect.target == null:
		push_error("effect has null target callable")
		return Result.Err("effect missing target callable")
	
	var target_result = effect.target.call(ctx)
	if target_result.is_err():
		return target_result
	var targets = target_result.unwrap()
	
	#push to chain stack WITHOUT resolving yet
	_chain_stack.append({effect = effect, targets = targets, ctx = ctx})
	
	return Result.Ok(null)

func _resolution_phase(effect: Effect, targets, ctx: Context) -> Result:
	#execute main action with floodgate modifications/replacements
	var action_result = _execute_action_with_floodgates(effect.action, ctx, targets)
	
	#handle activation negation (effect never resolves)
	if action_result.is_err():
		var err = action_result.unwrap_err()
		if err is ActivationNegated:
			#effect activation was negated
			#note: this is DIFFERENT from EffectNegated - activation negation means
			#the effect never happened at all, so we don't log it
			return Result.Err(err)
		elif err is EffectNegated:
			#effect was negated during resolution, log negation event
			var negation_event = TimingEvent.new("effect_negated", 2, {
				effect = effect,
				reason = err.reason
			})
			return _commit_phase([negation_event])
		return action_result
	
	var action_data: ActionResult = action_result.unwrap()
	var all_timing_events = action_data.timing_events.duplicate()
	
	#execute compound actions based on their type
	var previous_succeeded = action_data.succeeded
	
	for compound in effect.compound_actions:
		var should_execute = false
		
		match compound.type:
			CompoundType.AND:
				should_execute = true #always execute
			CompoundType.AND_THEN:
				should_execute = action_result.is_ok() #execute if previous didn't error
			CompoundType.AND_IF_YOU_DO:
				should_execute = previous_succeeded #execute if previous actually did something
			CompoundType.AND_THEN_IF_YOU_DO:
				should_execute = previous_succeeded #same as AND_IF_YOU_DO
		
		if should_execute:
			var compound_result = _execute_action_with_floodgates(compound.action, ctx, targets)
			
			if compound_result.is_ok():
				var compound_data: ActionResult = compound_result.unwrap()
				all_timing_events.append_array(compound_data.timing_events)
				previous_succeeded = compound_data.succeeded
			else:
				#compound action failed
				previous_succeeded = false
				#check for negation
				var err = compound_result.unwrap_err()
				if err is EffectNegated:
					var negation_event = TimingEvent.new("effect_negated", 2, {
						effect = effect,
						compound_index = effect.compound_actions.find(compound),
						reason = err.reason
					})
					all_timing_events.append(negation_event)
	
	return _commit_phase(all_timing_events)

func _execute_action_with_floodgates(action: Callable, ctx: Context, targets) -> Result:
	if action == null:
		push_error("attempted to execute null action")
		return Result.Err("null action")
	
	#first, check if any replace floodgates want to swap this action
	var final_action = action
	var final_targets = targets
	
	for floodgate in _active_floodgates:
		if floodgate.phase == Phase.RESOLUTION and floodgate.type == "replace":
			if floodgate.replace == null:
				push_warning("replace floodgate has null callable")
				continue
			
			#floodgate.replace takes (ctx, action_data) and returns new action or same action
			var replaced = floodgate.replace.call(ctx, {
				action = final_action,
				targets = final_targets
			})
			
			#validate return format
			if replaced != null and replaced is Dictionary:
				if replaced.has("action") and replaced.action != null:
					final_action = replaced.action
				if replaced.has("targets"):
					final_targets = replaced.targets
	
	#execute the (possibly replaced) action
	var result = final_action.call(ctx, final_targets)
	
	#if action succeeded, apply modify floodgates to the result
	if result.is_ok():
		var action_result = result.unwrap()
		
		#convert various return types to ActionResult
		if not (action_result is ActionResult):
			#if user returned timing events directly, wrap them
			if action_result is TimingEvent:
				action_result = ActionResult.new(true, [action_result])
			elif action_result is Array:
				action_result = ActionResult.new(true, action_result)
			elif action_result == null:
				action_result = ActionResult.new(false, [])
			elif action_result is bool:
				action_result = ActionResult.new(action_result, [])
			elif typeof(action_result) == TYPE_INT and action_result == 0:
				#0 might mean "nothing happened"
				action_result = ActionResult.new(false, [])
			else:
				#assume any other value indicates success (might be a bad idea later, any comments on this?)
				action_result = ActionResult.new(true, [])
		
		#apply modify floodgates to timing events
		for floodgate in _active_floodgates:
			if floodgate.phase == Phase.RESOLUTION and floodgate.type == "modify":
				if floodgate.modify == null:
					push_warning("modify floodgate has null callable")
					continue
				
				#let floodgate modify each timing event
				for i in range(action_result.timing_events.size()):
					var modified = floodgate.modify.call(ctx, action_result.timing_events[i])
					if modified != null:
						action_result.timing_events[i] = modified
		
		return Result.Ok(action_result)
	
	return result

func _commit_phase(timing_events: Array) -> Result:
	#add scope info to all timing events
	for event in timing_events:
		if event is TimingEvent:
			event.scope_stack = _current_scope_stack.duplicate(true) #might be a source of insane errors down the line
			event.timestamp = _timestamp
			_timestamp += 1
	
	_timing_history.append_array(timing_events)
	
	#find all triggers that match these timings
	for event in timing_events:
		if not (event is TimingEvent):
			continue
			
		for trigger in _active_triggers:
			if trigger.timing == event.timing and trigger.layer == event.layer:
				if trigger.filter == null:
					push_warning("trigger has null filter callable")
					continue
				
				if trigger.filter.call(event):
					if not _pending_responses.has(trigger):
						_pending_responses.append(trigger)
	
	return Result.Ok(null)

func _resolve_chain_stack() -> Result:
	#resolve chain in reverse order (last in, first out)
	#please see Yugioh's chain resolution rules for a reference.
	while _chain_stack.size() > 0:
		var entry = _chain_stack.pop_back()
		
		#effect already went through REQUEST, now do RESOLUTION -> COMMIT
		var resolution = _resolution_phase(entry.effect, entry.targets, entry.ctx)
		if resolution.is_err():
			var err = resolution.unwrap_err()
			#activation negated errors should be handled, but other errors stop the chain
			if not (err is ActivationNegated):
				return resolution
	
	return Result.Ok(null)

#endregion

#region Constraint Helpers

func check_once_per_turn(key: String) -> Result:
	if _constraint_tracker.has(key):
		return Result.Err(ConstraintViolated.new(key))
	return Result.Ok(null)

func mark_used(key: String) -> void:
	_constraint_tracker[key] = true

func check_times_per_turn(key: String, max_times: int) -> Result:
	var count = _constraint_tracker.get(key, 0)
	if count >= max_times:
		return Result.Err(ConstraintViolated.new(key))
	return Result.Ok(null)

func increment_usage(key: String) -> void:
	_constraint_tracker[key] = _constraint_tracker.get(key, 0) + 1

#endregion

#region Builder Classes

class EffectBuilder:
	var _evesses: Evesses
	var _effect: Effect
	var _has_action: bool = false
	
	func _init(ev: Evesses):
		_evesses = ev
		_effect = Effect.new()
	
	func cost(cost_func: Callable) -> EffectBuilder:
		_effect.cost = cost_func
		#by default, cost checker is the same as cost
		#user can override with cost_checker()
		_effect.cost_checker = cost_func
		return self
	
	func cost_checker(checker_func: Callable) -> EffectBuilder:
		_effect.cost_checker = checker_func
		return self
	
	func constraint(constraint_func: Callable) -> EffectBuilder:
		_effect.constraints.append(constraint_func)
		return self
	
	func once_per_turn(key: String = "") -> EffectBuilder:
		var actual_key = key if key != "" else str(_effect.get_instance_id())
		#note: constraint is marked during REQUEST phase, before resolution
		#this means "once per turn you can ACTIVATE this", not "once per turn this RESOLVES"
		#this is correct for yugioh-style effects but may surprise users from other games
		_effect.constraints.append(func(_ctx):
			var result = _evesses.check_once_per_turn(actual_key)
			if result.is_ok():
				_evesses.mark_used(actual_key)
			return result
		)
		return self
	
	func times_per_turn(max_times: int, key: String = "") -> EffectBuilder:
		var actual_key = key if key != "" else str(_effect.get_instance_id())
		_effect.constraints.append(func(_ctx):
			var result = _evesses.check_times_per_turn(actual_key, max_times)
			if result.is_ok():
				_evesses.increment_usage(actual_key)
			return result
		)
		return self
	
	func target(target_func: Callable) -> EffectBuilder:
		_effect.target = target_func
		return self
	
	func action(action_func: Callable) -> EffectBuilder:
		_effect.action = action_func
		_has_action = true
		return self
	
	func and_then(action_func: Callable) -> EffectBuilder:
		_effect.compound_actions.append({
			type = CompoundType.AND_THEN,
			action = action_func
		})
		return self
	
	func and_also(action_func: Callable) -> EffectBuilder:
		_effect.compound_actions.append({
			type = CompoundType.AND,
			action = action_func
		})
		return self
	
	func and_if_you_do(action_func: Callable) -> EffectBuilder:
		_effect.compound_actions.append({
			type = CompoundType.AND_IF_YOU_DO,
			action = action_func
		})
		return self
	
	func and_then_if_you_do(action_func: Callable) -> EffectBuilder:
		_effect.compound_actions.append({
			type = CompoundType.AND_THEN_IF_YOU_DO,
			action = action_func
		})
		return self
	
	func tag(tag_name: String) -> EffectBuilder:
		_effect.tags.append(tag_name)
		return self
	
	func bind_lifetime(node: Node) -> EffectBuilder:
		_effect.lifetime_node = node
		return self
	
	func build() -> Effect:
		if not _has_action:
			push_warning(
	"Effect built with no action set - will use stub that does nothing. You can bypass this by throwing in a function that just passes."
	)
		return _effect

class TriggerBuilder:
	var _evesses: Evesses
	var _trigger: Trigger
	var _has_action: bool = false
	
	func _init(ev: Evesses, timing: String, layer: int):
		_evesses = ev
		_trigger = Trigger.new(timing, layer)
	
	func filter(filter_func: Callable) -> TriggerBuilder:
		_trigger.filter = filter_func
		return self
	
	func optional() -> TriggerBuilder:
		_trigger.is_optional = true
		return self
	
	func mandatory() -> TriggerBuilder:
		_trigger.is_optional = false
		return self
	
	func once_per_turn(key: String = "") -> TriggerBuilder:
		var actual_key = key if key != "" else str(_trigger.get_instance_id())
		_trigger.effect.constraints.append(func(_ctx):
			var result = _evesses.check_once_per_turn(actual_key)
			if result.is_ok():
				_evesses.mark_used(actual_key)
			return result
		)
		return self
	
	func action(action_func: Callable) -> TriggerBuilder:
		_trigger.effect.action = action_func
		_has_action = true
		return self
	
	func and_then(action_func: Callable) -> TriggerBuilder:
		_trigger.effect.compound_actions.append({
			type = CompoundType.AND_THEN,
			action = action_func
		})
		return self
	
	func bind_lifetime(node: Node) -> TriggerBuilder:
		_trigger.lifetime_node = node
		return self
	
	func build() -> Trigger:
		if not _has_action:
			push_warning("Trigger built with no action set - will use stub that does nothing")
		_evesses._register_trigger(_trigger)
		return _trigger

class FloodgateBuilder:
	var _evesses: Evesses
	var _floodgate: Floodgate
	
	func _init(ev: Evesses):
		_evesses = ev
		_floodgate = Floodgate.new()
	
	func forbid(forbid_func: Callable) -> FloodgateBuilder:
		_floodgate.forbid = forbid_func
		_floodgate.type = "forbid"
		return self
	
	func modify(modify_func: Callable) -> FloodgateBuilder:
		_floodgate.modify = modify_func
		_floodgate.type = "modify"
		return self
	
	func replace(replace_func: Callable) -> FloodgateBuilder:
		_floodgate.replace = replace_func
		_floodgate.type = "replace"
		return self
	
	func phase(p: Phase) -> FloodgateBuilder:
		_floodgate.phase = p
		return self
	
	func layer(l: int) -> FloodgateBuilder:
		_floodgate.layer = l
		return self
	
	func bind_lifetime(node: Node) -> FloodgateBuilder:
		_floodgate.lifetime_node = node
		return self
	
	func build() -> Floodgate:
		if _floodgate.type == "none":
			push_warning("Floodgate built with no type (forbid/modify/replace) set")
		_evesses._register_floodgate(_floodgate)
		return _floodgate

#endregion

#region Context (stub - user implements)

class Context:
	#this is a stub that the user needs to extend
	#it should provide all the actual game actions
	#CRITICAL: actions should return Result.Ok(ActionResult.new(succeeded, events))
	#where 'succeeded' is true if the action actually did something meaningful
	
	var evesses: Evesses
	
	func _init(ev: Evesses):
		evesses = ev
	
	#example stub implementations
	func pay_lp(_amount: int) -> Result:
		push_error("pay_lp not implemented")
		return Result.Err("not implemented")
	
	func discard(_count: int) -> Result:
		push_error("discard not implemented")
		return Result.Err("not implemented")
	
	func select_cards(_count: int, _filter: Callable) -> Result:
		push_error("select_cards not implemented")
		return Result.Err("not implemented")
	
	func destroy(_targets) -> Result:
		push_error("destroy not implemented")
		return Result.Err("not implemented")
	
	func draw(_count: int) -> Result:
		push_error("draw not implemented")
		return Result.Err("not implemented")
	
	func banish(_targets) -> Result:
		push_error("banish not implemented")
		return Result.Err("not implemented")
	
	func check_once_per_turn(key: String) -> Result:
		return evesses.check_once_per_turn(key)
	
	func me():
		push_error("me() not implemented")
		return null

#endregion
