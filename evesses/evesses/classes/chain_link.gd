# ev_chain_link.gd
class_name EvChainLink
extends RefCounted

var source: Node
var tag: String
var context: EvContext
var steps: Array[EvEffectStep] = []

func _init(_source: Node, _tag: String, _context: EvContext, _steps: Array[EvEffectStep]):
	source = _source
	tag = _tag
	context = _context
	steps = _steps

## This is the core resolution logic called by Evesses.
func resolve(engine: Evesses) -> Result:
	# 1. Check for negations via Interceptors
	context = engine.apply_interceptors(context)
	if context.result.is_err():
		return context.result # Effect was negated/voided
	
	var last_result: Result = Result.Ok(null)
	
	# 2. Iterate through the compound actions
	for i in range(steps.size()):
		var step = steps[i]
		
		# Check logic for AND_THEN and AND_IF_YOU_DO
		if i > 0:
			if step.mode != EvEffectStep.Mode.AND and last_result.is_err():
				# Skip this step because the previous one failed
				continue
		
		# Perform the action on the live world
		last_result = step.action.call(engine.world, context)
		
		# If this was a "Sequential" step (AND_THEN), we might pause 
		# or emit a timing for other triggers to see mid-resolution.
		if step.mode == EvEffectStep.Mode.AND_THEN or step.mode == EvEffectStep.Mode.AND_THEN_IF_YOU_DO:
			engine.emit_sub_timing(tag + "_step_" + str(i))
			
	return last_result
