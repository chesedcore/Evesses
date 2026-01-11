class_name EvEffectBuilder
extends RefCounted

var _engine: Evesses
var _source: Node
var _tag: String = "effect"

# Activation Data
var _targeting_func: Callable # func(world) -> Result<Array[Node]>
var _cost_func: Callable      # func(world) -> Result

# Resolution Steps
var _steps: Array[EvEffectStep] = []

func _init(engine: Evesses, source: Node):
	_engine = engine
	_source = source

## Set the tag for history tracking and rule filtering
func named(tag_name: String) -> EvEffectBuilder:
	_tag = tag_name
	return self

## Step 1: Targeting. Runs during the Request phase.
func targeting(t_func: Callable) -> EvEffectBuilder:
	_targeting_func = t_func
	return self

## Step 2: Cost. Verified via simulation before payment.
func cost(c_func: Callable) -> EvEffectBuilder:
	_cost_func = c_func
	return self

## Step 3: The primary action (The first resolution step)
func action(a_func: Callable) -> EvEffectBuilder:
	_steps.append(EvEffectStep.new(a_func, EvEffectStep.Mode.AND))
	return self

# --- Compounders ---

func and_also(a_func: Callable) -> EvEffectBuilder:
	_steps.append(EvEffectStep.new(a_func, EvEffectStep.Mode.AND))
	return self

func and_then(a_func: Callable) -> EvEffectBuilder:
	_steps.append(EvEffectStep.new(a_func, EvEffectStep.Mode.AND_THEN))
	return self

func and_if_you_do(a_func: Callable) -> EvEffectBuilder:
	_steps.append(EvEffectStep.new(a_func, EvEffectStep.Mode.AND_IF_YOU_DO))
	return self

# --- The Request Pipeline ---

## Finalizes the effect and attempts to push it to the chain stack.
func request() -> Result:
	var context = EvContext.new()
	context.source = _source
	context.tags = [_tag]
	
	# 1. Evaluate Targeting
	if _targeting_func.is_valid():
		var t_result: Result = _targeting_func.call(_engine.world)
		if t_result.is_err():
			return t_result
		context.targets = t_result.unwrap() # Array[Node]
	
	# 2. Simulation (Cost & Floodgates)
	var sim_result: Result = _engine.simulate(func(sandbox_world):
		if _cost_func.is_valid():
			# Check if cost can be paid in the simulated world
			var c_res = _cost_func.call(sandbox_world)
			if c_res.is_err(): return c_res
		
		# Check if the activation itself is forbidden by rules
		var sim_ctx = _engine.apply_interceptors(context)
		return sim_ctx.result
	)
	
	if sim_result.is_err():
		return sim_result
	
	# 3. Pay the Cost (On the LIVE world)
	# Costs are non-negatable in YGO logic once simulation passes.
	if _cost_func.is_valid():
		_cost_func.call(_engine.world)
	
	# 4. Create the Chain Link and push to Stack
	var link = EvChainLink.new(_source, _tag, context, _steps)
	_engine.push_to_chain(link)
	
	return Result.Ok(link)
