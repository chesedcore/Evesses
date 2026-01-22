# Evesses
Evesses (from "**Eve**nt **Sys**tem") is a tag-driven, transactional event pipeline with temporal scope and a tracked history.

It is heavily inspired by the Yu-Gi-Oh! TCG's effect activation, resolution and rule mutation system.

This system tries to carve out the heart behind Yu-Gi-Oh!, and make it as generic as possible, so it can be used for other games like RPGs, roguelikes and strategy titles that may benefit from such a system.

---

## Philosophy

### 1. Tag-driven
Evesses uses 'tags' to denote action identity. These tags declare a label over an action so that they may be intercepted by other listeners or rule-changing effects, and mutated accordingly.

### 2. Transactional event pipeline
Evesses achieves fine-grain rule mutation by breaking down bigger effects into smaller, atomic actions that can be mutated individually. These actions are then cast into a pipeline where they are exposed to the rest of the world (the 'Context').

### 3. Temporal Scope
Evesses assumes no knowledge of the game's temporal units that it is used on. Card games most frequently use the phrase 'turn,' but they might also break down a turn into several 'phases,' where a 'turn' wraps different 'phases.' Evesses is flexible in this regard, and you can directly state such temporal scopes, and layer them accordingly.

### 4. Tracked History
Evesses holds a history of events that pass through the pipeline, so it is possible to reference actions that previously happened and use them as basis for other effects.

---

# Usage Guide

## Table of Contents
0. [Quick Overview](#quick-start)
1. [Setup](#setup)
2. [Extending Context](#extending-context)
3. [Direct Effects](#direct-effects)
4. [Trigger Effects](#trigger-effects)
5. [Floodgates](#floodgates)
6. [Temporal Scopes](#temporal-scopes)
7. [Chain Resolution](#chain-resolution)
8. [Advanced Patterns](#advanced-patterns)
9. [More Info](#more-info)

---

## Quick Start

An effect is either a ["Direct Effect"](#direct-effects) (activated by the player as a consequence of their input),
or a ["Trigger Effect"](#trigger-effects) (effects that are pre-registered on the system that react to other systems).
There are also ["Floodgates"](#floodgates) (effects that modify or negate other effects).
Once you're done reading up, see [chain resolution](#chain-resolution) to learn how to activate and resolve an effect.

Here is an example showing you how the system functions:
```gdscript
class MyCtx: #a mini context holding a small world state for demo purposes
    var hand = ["A","B","C","D"]
    var lp = 8000
    func draw(n):
        var drawn = []
        for i in n:
            if hand.empty(): break
            drawn.append(hand.pop_back())
        return drawn
    func gain_lp(n):
        lp += n

var ctx = MyCtx.new()
var ev = Evesses.new()

# Trigger! gain 500 LP when a card is drawn
ev.on_timing("card_drawn", 2).mandatory().action(func(c,e):
    c.gain_lp(500)
    return some()
).build()

# Effect! draw 2 cards
var pot = ev.direct_effect().action(func(c,_):
    var drawn = c.draw(2)
    for card in drawn:
        ev.add_timing(Evesses.TimingEvent.new("card_drawn",2,{"card":card,"player":c}))
    return some()
).build()

# Activate effect and resolve chain like as such
ev.activate_effect(pot, ctx)
ev.resolve_chain(ctx)

print("Hand:", ctx.hand)
print("LP:", ctx.lp)
```


## Setup

### Dependencies

Evesses requires at least **Godot 4.5** to function. This is the most recent version of Godot that has been tested.

Evesses comes bundled with Tienne K's `godot-optional` addon. [You can find it here.](https://github.com/WhoStoleMyCoffee/godot-optional)
This is used for robust error and result handling, a sector that Godot is severely lacking in.

### Initialisation

Evesses is not an autoload. It must be initialised by creating a new instance of it, and then put into your preferred node that is
going to host Evesses. You may either put it into an autoload, or a central level handler node, as it is designed to be flexible.

```gdscript
# Create the evesses instance
var ev: Evesses = Evesses.new()

# Create your game context (see next section)
var ctx: MyGameContext = MyGameContext.new(ev)
```

### Understanding the Result Type

As an extremely quick "get up to speed" explanation:
It represents an operation result that, either:
- was successful and contains the output of the operation, or
- failed, and contains the reason for the failure.

A successful `Result` can be created with `Result.Ok(output)`, and a failed `Result`, with `Result.Err("reason")`. If there is no output,
simply use `Result.Ok(null)`.

### Understanding the Option Type

An `Option` represents a value that may or may not exist:
- `Option.Some(value)` - contains a value
- `Option.None()` - no value present

In Evesses, actions return `Result.Ok(Option.Some(events))` when they do something, and `Result.Ok(Option.None())` when they don't, and `Result.Err(...)` when it's not possible to even perform that action in the first place.

[Why can't I just use a Result?](#why-should-i-use-option-wrapped-within-a-result-for-my-actions)

---

## Extending Context

**You MUST extend `Evesses.Context` with your actual game logic.** This is where you implement all the concrete actions your game needs.

**CRITICAL:** All action methods must return:
- `Result.Ok(Option.Some(events))` - when the action did something
- `Result.Ok(Option.None())`       - when the action did nothing (e.g., tried to destroy an indestructible card)
- `Result.Err(...)`                - when the action cannot proceed (negation, errors)

I recognise that typing:
```gdscript
return Result.Ok(Option.Some([Evesses.TimingEvent.new("thing", 2)]))
```
is not exactly ideal.

This is why Evesses provides two helper methods in `Context`:

### Context Helpers

```gdscript
# Return success with timing events
some(event1: Evesses.TimingEvent, event2: Evesses.TimingEvent, event3: Evesses.TimingEvent) -> Result  # Multiple events
some(event: Evesses.TimingEvent) -> Result                                                              # Single event
some() -> Result                                                                                        # No events (still succeeded)

# Return "nothing happened" but effect still resolved
none() -> Result
```

### Example Implementation

```gdscript
class_name MyGameContext
extends Evesses.Context

var world: GameWorld  # Your game state
var current_player: Player

func _init(evesses: Evesses) -> void:
	super(evesses)
	world = GameWorld.new()

# Implement all the game actions
func pay_lp(amount: int) -> Result:
	if current_player.life_points < amount:
		return Result.Err(Evesses.CostCannotBePaid.new("not enough LP"))
	
	current_player.life_points -= amount
	return some()  # Paid successfully, no events generated

func discard(count: int) -> Result:
	if current_player.hand.size() < count:
		return Result.Err(Evesses.CostCannotBePaid.new("not enough cards"))
	
	var discarded: Array[Card] = []
	for i in count:
		var card: Card = current_player.hand.pop_back()
		current_player.graveyard.append(card)
		discarded.append(card)
	
	var event: Evesses.TimingEvent = Evesses.TimingEvent.new("card_discarded", 2, {
		"cards": discarded,
		"player": current_player
	})
	return some(event)

func destroy(targets: Array) -> Result:
	var destroyed: Array[Card] = []
	for card: Card in targets:
		if card.is_indestructible:
			continue  # Skip indestructible cards
		card.destroy()
		destroyed.append(card)
	
	# IMPORTANT: return none() if nothing was destroyed
	if destroyed.is_empty():
		return none()
	
	var event: Evesses.TimingEvent = Evesses.TimingEvent.new("card_destroyed", 2, {
		"cards": destroyed
	})
	return some(event)

func select_cards(count: int, filter: Callable) -> Result:
	# This would typically open a UI for the player to select
	var available: Array = world.get_all_cards().filter(filter)
	if available.size() < count:
		return Result.Err("not enough valid targets")
	
	# For now, auto-select first N cards
	var selected: Array = available.slice(0, count)
	return Result.Ok(selected)
```

---

## Direct Effects

Direct effects are activated manually by the player. These represent cards like spells, traps, and activated monster effects.

### Simple Effect: Pot of Greed

```gdscript
# "draw 2 cards"
var pot_of_greed: Evesses.Effect = ev.direct_effect() \
	.action(func(ctx: Evesses.Context, _targets: Variant) -> Result:
		return ctx.draw(2)) \
	.build()

# Activate it
var result: Result = ev.activate_effect(pot_of_greed, ctx)
if result.is_err():
	print("couldn't activate: ", result.unwrap_err())

# Resolve the chain
ev.resolve_chain(ctx)
```

### Effect with Cost: Raigeki Break

```gdscript
# "discard 1 card; target 1 card; destroy that target"
var raigeki_break: Evesses.Effect = ev.direct_effect() \
	.cost(func(ctx: Evesses.Context) -> Result:
		return ctx.discard(1)) \
	.target(func(ctx: Evesses.Context) -> Result:
		return ctx.select_cards(1, func(card: Card) -> bool: return true)) \
	.action(func(ctx: Evesses.Context, targets: Variant) -> Result:
		return ctx.destroy(targets[0])) \
	.build()
```

### Effect with Compounds: Monster Reborn

```gdscript
# "target 1 monster in any graveyard; special summon it, and then, gain 500 LP"
var monster_reborn: Evesses.Effect = ev.direct_effect() \
	.target(func(ctx: Evesses.Context) -> Result:
		return ctx.select_cards(1, func(card: Card) -> bool: 
			return card.is_monster() and card.is_in_graveyard())) \
	.action(func(ctx: Evesses.Context, targets: Variant) -> Result:
		return ctx.special_summon(targets[0])) \
	.and_then(func(ctx: Evesses.Context, _targets: Variant) -> Result:
		return ctx.gain_lp(500)) \
	.build()
```

### Compound Types

Evesses supports four compound types that determine when subsequent actions execute:

#### `.and_also(action)` (CompoundType.AND)
Always executes, regardless of previous action's outcome.

```gdscript
# "draw 1 card and gain 500 LP"
# Both happen regardless
.action(func(ctx: Evesses.Context, _targets: Variant) -> Result: return ctx.draw(1)) \
.and_also(func(ctx: Evesses.Context, _targets: Variant) -> Result: return ctx.gain_lp(500))
```

#### `.and_then(action)` (CompoundType.AND_THEN)
Executes if previous action didn't error (returned `Result.Ok`).

```gdscript
# "draw 1 card, and then gain 500 LP"
# LP gain happens even if draw did nothing (deck empty returns Ok(None))
.action(func(ctx: Evesses.Context, _targets: Variant) -> Result: return ctx.draw(1)) \
.and_then(func(ctx: Evesses.Context, _targets: Variant) -> Result: return ctx.gain_lp(500))
```

#### `.and_if_you_do(action)` (CompoundType.AND_IF_YOU_DO)
Executes only if previous action actually did something (returned `Option.Some`).

```gdscript
# "destroy 1 card; if you do, draw 1 card"
# Only draws if destruction succeeded
.action(func(ctx: Evesses.Context, targets: Variant) -> Result: return ctx.destroy(targets[0])) \
.and_if_you_do(func(ctx: Evesses.Context, _targets: Variant) -> Result: return ctx.draw(1))
```

#### `.and_then_if_you_do(action)` (CompoundType.AND_THEN_IF_YOU_DO)
Same as `.and_if_you_do()` - executes only if previous actually did something.

### Effect with Constraint: Once Per Turn

```gdscript
# "once per turn: destroy 1 card"
var effect: Evesses.Effect = ev.direct_effect() \
	.once_per_turn("my_effect_key") \  # Auto-generates key if not provided
	.target(func(ctx: Evesses.Context) -> Result:
		return ctx.select_cards(1, func(card: Card) -> bool: return true)) \
	.action(func(ctx: Evesses.Context, targets: Variant) -> Result:
		return ctx.destroy(targets[0])) \
	.build()
```

### Effect with Tags

```gdscript
# Useful for floodgates to check effect types
var spell_effect: Evesses.Effect = ev.direct_effect() \
	.tag("spell") \
	.tag("quickplay") \
	.action(func(ctx: Evesses.Context, _targets: Variant) -> Result:
		return ctx.draw(1)) \
	.build()
```

---

## Trigger Effects

Triggers activate automatically when specific timing events occur. They're registered once and listen continuously.

### Simple Trigger: Draw on Destruction

```gdscript
# "when a monster you control is destroyed: draw 1 card"
var trigger: Evesses.TriggerEffect = ev.on_timing("card_destroyed", 2) \
	.filter(func(event: Evesses.TimingEvent) -> bool:
		return event.data.cards.any(func(c: Card) -> bool: 
			return c.is_monster() and c.controller == ctx.me())) \
	.action(func(ctx: Evesses.Context, event: Evesses.TimingEvent) -> Result:
		return ctx.draw(1)) \
	.build()

# Trigger is now registered and will auto-activate when its timing occurs
```

### Optional Trigger

```gdscript
# "when a card is sent to the GY: you can draw 1 card"
var optional_trigger: Evesses.TriggerEffect = ev.on_timing("card_sent_to_gy", 2) \
	.optional() \  # Player chooses whether to activate
	.action(func(ctx: Evesses.Context, event: Evesses.TimingEvent) -> Result:
		return ctx.draw(1)) \
	.build()
```

### Mandatory Trigger with Constraint

```gdscript
# "once per turn, when you take damage: gain 1000 LP"
var recovery_trigger: Evesses.TriggerEffect = ev.on_timing("damage_taken", 2) \
	.mandatory() \
	.once_per_turn("recovery_trigger") \
	.filter(func(event: Evesses.TimingEvent) -> bool:
		return event.data.player == ctx.me()) \
	.action(func(ctx: Evesses.Context, event: Evesses.TimingEvent) -> Result:
		return ctx.gain_lp(1000)) \
	.build()
```

### Trigger Bound to Lifetime

```gdscript
# This trigger only exists while the card is on the field
var card_node: Node = get_this_card() #some magic function that obtains your card

var field_trigger: Evesses.TriggerEffect = ev.on_timing("monster_summoned", 2) \
	.action(func(ctx: Evesses.Context, event: Evesses.TimingEvent) -> Result:
		return ctx.gain_lp(500)) \
	.bind_lifetime(card_node) \  # Auto-unregisters when node dies/signals
	.build()

# When card_node emits "lifetime_expired" or is freed, trigger unregisters
```

---

## Floodgates

Floodgates are continuous effects that modify, forbid, or replace actions. They apply passively.

### Forbid Type: Spell Seal

```gdscript
# "neither player can activate spell cards"
var spell_seal_node: Node = get_this_card() #magic function that gets your card (make a query API or something)

var spell_seal: Evesses.Floodgate = ev.floodgate() \
	.forbid(func(ctx: Evesses.Context, effect: Evesses.Effect) -> bool:
		return effect.tags.has("spell")) \
	.phase(Evesses.Phase.REQUEST) \  # Check during activation
	.bind_lifetime(spell_seal_node) \
	.build()

# Now any effect with tag "spell" will return Err(ActionForbidden)
```

### Modify Type: Field Boost

```gdscript
# "all monsters gain 500 ATK"
# Modify floodgates receive TimingEvents and can modify them
var field_boost: Evesses.Floodgate = ev.floodgate() \
	.modify(func(ctx: Evesses.Context, timing_event: Variant) -> Variant:
		# Modify timing events as they're generated
		if timing_event is Evesses.TimingEvent:
			if timing_event.timing == "stat_query" and timing_event.data.get("stat") == "atk":
				timing_event.data.value += 500
		return timing_event) \
	.phase(Evesses.Phase.RESOLUTION) \
	.layer(2) \  # Layer determines application order
	.bind_lifetime(field_spell_node) \
	.build()

# Note: you'd need to implement a stat query system where checking stats
# generates timing events that floodgates can modify
```

### Replace Type: Macro Cosmos

```gdscript
# "cards that would be sent to the GY are banished instead"
var macro_cosmos: Evesses.Floodgate = ev.floodgate() \
	.replace(func(ctx: Evesses.Context, action_data: Dictionary) -> Dictionary:
		# action_data is {action: Callable, targets: Variant}
		# Check if this is a "send to graveyard" action
		# (you'd need to tag your actions or check some property)
		if action_data.has("type") and action_data.type == "send_to_graveyard":
			# Return new action that banishes instead
			return {
				"action": func(c: Evesses.Context, t: Variant) -> Result: return c.banish(t),
				"targets": action_data.targets
			}
		# Don't modify other actions
		return action_data) \
	.phase(Evesses.Phase.RESOLUTION) \
	.bind_lifetime(macro_node) \
	.build()

# Note: for this to work, your Context actions need to include metadata
# or you need to wrap actions in a way that floodgates can identify them
```

### Multiple Floodgates with Layers

```gdscript
# Layer 1 applies first, then layer 2, etc.
# If same layer, insertion order determines application order
var boost_1: Evesses.Floodgate = ev.floodgate() \
	.modify(func(ctx: Evesses.Context, query: Variant) -> Variant: return query.value + 100) \
	.layer(1) \
	.build()

var boost_2: Evesses.Floodgate = ev.floodgate() \
	.modify(func(ctx: Evesses.Context, query: Variant) -> Variant: return query.value * 2) \
	.layer(2) \
	.build()

# Result: (base + 100) * 2
```

---

## Temporal Scopes

Temporal scopes define the "when" of your game. They're hierarchical and user-defined. Some games use 'turn's, some use 'year's, blah blah.

### Defining Scopes

```gdscript
# Enter a turn (layer 1 scope)
ev.timing("turn", 1)

# Enter a phase within that turn (layer 2 scope)
ev.timing("main_phase", 2)

# Enter a step within that phase (layer 3 scope)
ev.timing("battle_step", 3)

# Exit scopes when done
ev.end_timing("battle_step")
ev.end_timing("main_phase")
ev.end_timing("turn")
```

### Scope-Aware Triggers

```gdscript
# Only trigger during the battle phase
var battle_trigger: Evesses.TriggerEffect = ev.on_timing("monster_destroyed", 2) \
	.filter(func(event: Evesses.TimingEvent) -> bool:
		# Check if we're in battle phase scope
		return event.scope_stack.any(func(s: Evesses.ScopeInfo) -> bool: 
			return s.scope == "battle_phase")) \
	.action(func(ctx: Evesses.Context, event: Evesses.TimingEvent) -> Result:
		return ctx.draw(1)) \
	.build()
```

### Typical Game Flow

```gdscript
func run_turn(player: Player) -> void:
	ctx.current_player = player
	ev.timing("turn", 1)
	
	# Draw phase
	ev.timing("draw_phase", 2)
	var draw_result: Result = ctx.draw(1)
	if draw_result.is_ok():
		ev.resolve_chain(ctx)  # Process triggers that respond to the draw
	ev.end_timing("draw_phase")
	
	# Main phase
	ev.timing("main_phase", 2)
	# Player actions here
	ev.end_timing("main_phase")
	
	# Battle phase
	ev.timing("battle_phase", 2)
	# Battle logic here
	ev.end_timing("battle_phase")
	
	# End phase
	ev.timing("end_phase", 2)
	ev.clear_constraint_tracker()  # Reset once per turn effects
	ev.end_timing("end_phase")
	
	ev.end_timing("turn")
```

---

## Chain Resolution

Chains build when effects activate, then resolve in reverse order (last in, first out - LIFO).
It's basically stack unwinding chain resolution from YGO.

### How Chain Building and Resolution Works

Here's a detailed example showing the entire flow:

```gdscript
# === SETUP ===
# Player has a monster on field
# Opponent has a trap card "Mirror Force" (destroys all attack position monsters when attacked)
# Player also has a relic "Draw on Destruction" (when monster destroyed, draw 1 card)

# === STEP 1: PLAYER ACTIVATES ATTACK ===
var attack_effect: Evesses.Effect = ev.direct_effect() \
	.action(func(ctx: Evesses.Context, _targets: Variant) -> Result:
		return ctx.attack_with_monster(player_monster)) \
	.build()

ev.activate_effect(attack_effect, ctx)
# What happens internally:
# - Goes through REQUEST phase:
#   * Checks constraints (can attack?)
#   * Pays cost (none)
#   * Selects targets (opponent's monster)
# - Adds to chain stack: [attack_effect]
# - Returns Result.Ok(null)
# - Does NOT resolve yet!

print(ev._chain_stack.size())  # 1

# === STEP 2: OPPONENT RESPONDS WITH MIRROR FORCE ===
var mirror_force: Evesses.Effect = ev.direct_effect() \
	.tag("trap") \
	.action(func(ctx: Evesses.Context, _targets: Variant) -> Result:
		var monsters: Array = ctx.get_all_attack_position_monsters(ctx.opponent())
		return ctx.destroy(monsters)) \
	.build()

ev.activate_effect(mirror_force, ctx)
# What happens internally:
# - Goes through REQUEST phase
# - Adds to chain stack: [attack_effect, mirror_force]
# - Still does NOT resolve!

print(ev._chain_stack.size())  # 2

# === STEP 3: PLAYER CHAINS ANOTHER CARD ===
var protection: Evesses.Effect = ev.direct_effect() \
	.action(func(ctx: Evesses.Context, _targets: Variant) -> Result:
		return ctx.make_indestructible(player_monster)) \
	.build()

ev.activate_effect(protection, ctx)
# Chain stack now: [attack_effect, mirror_force, protection]

print(ev._chain_stack.size())  # 3

# === STEP 4: NO MORE RESPONSES - RESOLVE THE CHAIN ===
ev.resolve_chain(ctx)

# What happens internally (in order):
# ┌─────────────────────────────────────────────────────────┐
# │ RESOLUTION BEGINS (Last In, First Out)                  │
# └─────────────────────────────────────────────────────────┘

# [1] Protection resolves (last activated, resolves first)
#     - RESOLUTION phase:
#       * Execute action: make_indestructible()
#       * Returns some(event)
#     - COMMIT phase:
#       * Add event to history
#       * Check for triggers (none match)
#     - Pop from stack
#     Chain stack now: [attack_effect, mirror_force]

# [2] Mirror Force resolves (second to last)
#     - RESOLUTION phase:
#       * Execute action: destroy all attack position monsters
#       * Player's monster is now indestructible (from protection!)
#       * Returns none() (nothing destroyed)
#     - COMMIT phase:
#       * No events generated (nothing destroyed)
#       * Check for triggers (none)
#     - Pop from stack
#     Chain stack now: [attack_effect]

# [3] Attack resolves (first activated, resolves last)
#     - RESOLUTION phase:
#       * Execute action: attack_with_monster()
#       * Damage is dealt
#       * Returns some(damage_event)
#     - COMMIT phase:
#       * Add damage_event to history
#       * Check for triggers (none match this timing)
#     - Pop from stack
#     Chain stack now: []

# ┌─────────────────────────────────────────────────────────┐
# │ CHAIN STACK EMPTY - Check for pending triggers          │
# └─────────────────────────────────────────────────────────┘

# No pending triggers, resolve_chain returns

print("Chain resolved!")
```

### Example with Triggers: The Full Pipeline

Here's a more complex example showing triggers activating mid-chain:

```gdscript
# === SETUP ===
# Player has:
# - A card that says "destroy 1 card"
# - A relic: "when a card is destroyed, draw 1 card"
# - Another relic: "when you draw a card, gain 500 LP"

# Register the relics as triggers
var draw_relic: Evesses.TriggerEffect = ev.on_timing("card_destroyed", 2) \
	.mandatory() \
	.action(func(ctx: Evesses.Context, event: Evesses.TimingEvent) -> Result:
		print("  [TRIGGER] Draw relic activating...")
		return ctx.draw(1)) \
	.build()

var lp_relic: Evesses.TriggerEffect = ev.on_timing("card_drawn", 2) \
	.mandatory() \
	.action(func(ctx: Evesses.Context, event: Evesses.TimingEvent) -> Result:
		print("  [TRIGGER] LP relic activating...")
		return ctx.gain_lp(500)) \
	.build()

# === ACTIVATION ===
var destroy_effect: Evesses.Effect = ev.direct_effect() \
	.target(func(ctx: Evesses.Context) -> Result: 
		return ctx.select_cards(1, func(c: Card) -> bool: return true)) \
	.action(func(ctx: Evesses.Context, targets: Variant) -> Result:
		print("[EFFECT] Destroying card...")
		return ctx.destroy(targets[0])) \
	.build()

print("=== PLAYER ACTIVATES DESTROY EFFECT ===")
ev.activate_effect(destroy_effect, ctx)
print("Chain stack size: ", ev._chain_stack.size())  # 1
print("")

print("=== RESOLVING CHAIN ===")
ev.resolve_chain(ctx)

# Hi, Monarch here to tell you how exactly this would resolve!
# What actually happens:
# 
# === PLAYER ACTIVATES DESTROY EFFECT ===
# Chain stack size: 1
# 
# === RESOLVING CHAIN ===
# [EFFECT] Destroying card...
#   -> Card destroyed
#   -> TimingEvent("card_destroyed") created
#   -> COMMIT phase adds event to history
#   -> Draw relic trigger matches timing!
#   -> Added to pending_responses
# 
# ┌─────────────────────────────────────────────────────────┐
# │ Chain stack empty, but pending_responses has 1 trigger  │
# │ Process pending responses...                            │
# └─────────────────────────────────────────────────────────┘
# 
#   [TRIGGER] Draw relic activating...
#     -> REQUEST phase: add to chain stack
#     -> Chain stack now: [draw_relic_effect]
# 
# ┌─────────────────────────────────────────────────────────┐
# │ Resolve the new chain                                   │
# └─────────────────────────────────────────────────────────┘
# 
#   [TRIGGER] Draw relic activating...
#     -> RESOLUTION phase: execute draw action
#     -> Card drawn
#     -> TimingEvent("card_drawn") created
#     -> COMMIT phase adds event to history
#     -> LP relic trigger matches timing!
#     -> Added to pending_responses
# 
# ┌─────────────────────────────────────────────────────────┐
# │ Chain stack empty, but pending_responses has 1 trigger  │
# │ Process pending responses...                            │
# └─────────────────────────────────────────────────────────┘
# 
#   [TRIGGER] LP relic activating...
#     -> REQUEST phase: add to chain stack
#     -> Chain stack now: [lp_relic_effect]
# 
# ┌─────────────────────────────────────────────────────────┐
# │ Resolve the new chain                                   │
# └─────────────────────────────────────────────────────────┘
# 
#   [TRIGGER] LP relic activating...
#     -> RESOLUTION phase: execute gain_lp action
#     -> LP gained
#     -> No timing events generated
#     -> COMMIT phase: no triggers match
# 
# ┌─────────────────────────────────────────────────────────┐
# │ Chain stack empty AND pending_responses empty           │
# │ resolve_chain() returns                                 │
# └─────────────────────────────────────────────────────────┘
# 
# Final result:
# - Card destroyed
# - Card drawn (from trigger)
# - 500 LP gained (from trigger on draw)
```

### The Three Phases Explained

Every effect that resolves goes through three phases:

#### REQUEST Phase
- **When**: Effect is activated (via `activate_effect()`)
- **What happens**:
  1. Check all constraints (once per turn, etc)
  2. Check if any floodgates forbid activation
  3. Check if cost can be paid
  4. Pay the cost (irreversible!)
  5. Select targets
  6. Add effect to chain stack
- **Result**: `Result.Ok(null)` if successful, `Result.Err(...)` if something prevents activation
- **Key point**: Effect does NOT execute yet! Just gets added to the chain.

#### RESOLUTION Phase
- **When**: During `resolve_chain()`, effects are popped from stack
- **What happens**:
  1. Execute main action (with any floodgate replacements)
  2. Check for effect negation
  3. Apply modify floodgates to generated events
  4. Execute compound actions (and_then, and_if_you_do, etc)
  5. Collect all timing events
- **Result**: `Result.Ok(null)` proceeds to COMMIT, `Result.Err(EffectNegated)` still commits negation event
- **Key point**: This is where effects actually DO things

#### COMMIT Phase
- **When**: Immediately after RESOLUTION phase
- **What happens**:
  1. Add scope info (turn, phase, etc) to all timing events
  2. Add events to history
  3. Find all triggers that match these timing events
  4. Add matching triggers to pending_responses
- **Result**: Always `Result.Ok(null)`
- **Key point**: Triggers don't activate here, they're just queued for next iteration

### Basic Chain Flow

```gdscript
# Player activates an effect (goes through REQUEST phase only)
var result: Result = ev.activate_effect(some_effect, ctx)
if result.is_err():
	print("couldn't activate")
	return

# Allow opponent to respond (their effects also go through REQUEST only)
ev.activate_effect(opponent_response, ctx)

# Now resolve the entire chain
ev.resolve_chain(ctx)

# resolve_chain will:
# 1. resolve all effects in reverse order (RESOLUTION -> COMMIT for each)
# 2. process any triggers that activated from the chain
# 3. resolve those triggers too if any activated
# 4. continue until both chain stack and pending responses are empty
```

### SEGOC Sorting

SEGOC (Simultaneous Effects Go On Chain) determines the order triggers activate when multiple trigger at once.

Feel free to suggest a better term for it because this term has been directly airlifted from Yugioh and probably sounds too obtuse.
Trust me, I know you. I'm in your walls.

```gdscript
# Set custom SEGOC sorter
ev.set_segoc_sorter(func(triggers: Array) -> Array:
	var mandatory: Array[Evesses.TriggerEffect] = []
	var turn_player_optional: Array[Evesses.TriggerEffect] = []
	var opponent_optional: Array[Evesses.TriggerEffect] = []
	
	for trigger: Evesses.TriggerEffect in triggers:
		if not trigger.is_optional:
			mandatory.append(trigger)
		elif trigger.effect.owner == ctx.current_player:
			turn_player_optional.append(trigger)
		else:
			opponent_optional.append(trigger)
	
	# In yugioh, the order is as such: mandatory, then turn player optional, then opponent optional
	return mandatory + turn_player_optional + opponent_optional
)
```

### Handling Chains Manually

```gdscript
# Build a chain by activating multiple effects
ev.activate_effect(effect1, ctx)  # Added to chain
ev.activate_effect(effect2, ctx)  # Added to chain
ev.activate_effect(effect3, ctx)  # Added to chain

# Resolve the entire chain in reverse order
ev.resolve_chain(ctx)
# Resolves: effect3 -> effect2 -> effect1
# Then processes any triggers that activated during resolution
```

---

## Advanced Patterns

### Multi-Target Effects

```gdscript
# "target up to 3 monsters; destroy them"
var effect: Evesses.Effect = ev.direct_effect() \
	.target(func(ctx: Evesses.Context) -> Result:
		return ctx.select_cards_up_to(3, func(card: Card) -> bool: return card.is_monster())) \
	.action(func(ctx: Evesses.Context, targets: Variant) -> Result:
		var events: Array[Evesses.TimingEvent] = []
		for target: Card in targets:
			var result: Result = ctx.destroy(target)
			if result.is_ok():
				var option: Option = result.unwrap()
				if option.is_some():
					var event_array: Array = option.unwrap()
					events.append_array(event_array)
		return ctx.some(events)) \
	.build()
```

### Conditional Compounds

```gdscript
# "destroy 1 card; if you do, draw 1 card"
var effect: Evesses.Effect = ev.direct_effect() \
	.target(func(ctx: Evesses.Context) -> Result: 
		return ctx.select_cards(1, func(c: Card) -> bool: return true)) \
	.action(func(ctx: Evesses.Context, targets: Variant) -> Result:
		return ctx.destroy(targets[0])) \  # Must return Option.Some for draw to execute
	.and_if_you_do(func(ctx: Evesses.Context, _targets: Variant) -> Result:
		# Only executes if destroy actually succeeded (destroyed.size() > 0)
		return ctx.draw(1)) \
	.build()

# The destroy action MUST return ctx.some(event) for draw to execute
# If destroy returns ctx.none() (nothing destroyed), draw won't execute
```

### Effect Negation

```gdscript
# From within your context
func negate_effect() -> Result:
	return Result.Err(Evesses.EffectNegated.new("negated by trap"))

# The effect still gets logged in history with an "effect_negated" event
```

### Checking History

```gdscript
# Get all timing events that happened
var history: Array[Evesses.TimingEvent] = ev.get_timing_history()

# Check if something happened this turn
var monsters_summoned: Array = history.filter(func(event: Evesses.TimingEvent) -> bool:
	return event.timing == "monster_summoned" and \
	       event.scope_stack.any(func(s: Evesses.ScopeInfo) -> bool: return s.scope == "turn")
)
```

### Lifetime Binding Patterns

```gdscript
# Trigger expires when card leaves field
card_node.lifetime_expired.connect(func() -> void:
	print("trigger cleaned up!")
)

var trigger: Evesses.TriggerEffect = ev.on_timing("something", 2) \
	.action(func(ctx: Evesses.Context, event: Evesses.TimingEvent) -> Result: 
		return ctx.do_thing()) \
	.bind_lifetime(card_node) \
	.build()

# Manually expire
card_node.lifetime_expired.emit()
```

### Setting Infinite Loop Protection

```gdscript
# Default is 1000 iterations
ev.set_max_chain_iterations(5000)  # Allow longer chains!
```

---

## Shit to Remember

1. **Always extend Context with your actual game actions** - the base Context is just stubs lol
2. **Actions must return Result<Option>** - `ctx.some(...events)` or `ctx.none()`
3. **Set Option correctly** - "if you do" compounds depend on Some/None
4. **Call resolve_chain** - `resolve_chain` handles both the chain and triggers
5. **Return TimingEvents from actions** - this is how triggers know what happened
6. **Use layers correctly** - higher layer = more nested (turn wraps phase wraps step)
7. **Floodgates need phases** - REQUEST for forbid, RESOLUTION for modify/replace
8. **Compound actions check previous result** - "and then" checks is_ok(), "if you do" checks is_some()
9. **Once per turn tracking** - call `clear_constraint_tracker()` at turn end
10. **Constraints marked at activation** - "once per turn" is marked during REQUEST phase, not RESOLUTION. This means "once per turn you can activate" not "once per turn this resolves". If negated, still counts as used.
11. **Infinite loop protection** - `resolve_chain` has a max iteration limit (default 1000). Change with `ev.set_max_chain_iterations(n)`
12. **Floodgate order** - same-layer floodgates apply in insertion order. First registered = first applied.
13. **Lifetime binding** - nodes must emit `lifetime_expired` signal OR be freed/destroyed. Both are handled automatically.
14. **Harass me** - on Discord as monarch_zero or here as an issue when you run into an issue.

---

## More info

### Why should I use Option wrapped within a Result for my actions?

**Short answer:** Because "operation failed" and "operation succeeded but did nothing" are different things.

**Long answer:**

`Result` answers, "Did the operation complete or error out?"
`Option` answers, "Did the action have its intended effect?"

These are different questions. Consider:

```gdscript
# Scenario 1: Can't activate (Result.Err)
func destroy(card: Card) -> Result:
	if not has_valid_target():
		return Result.Err("no valid targets")  # CAN'T even activate
	# ...

# Scenario 2: Activated but did nothing (Result.Ok(Option.None))
func destroy(card: Card) -> Result:
	if card.is_indestructible:
		return none()  # Activated, just nothing happened
	# ...

# Scenario 3: Activated and did something (Result.Ok(Option.Some))
func destroy(card: Card) -> Result:
	card.move_to_graveyard()
	return some(event)  # Activated and destroyed
```

**Why this matters for compounds**

```gdscript
# "Destroy a card, and if you do, draw 1 card"
.action(func(ctx: Evesses.Context, targets: Variant) -> Result: 
	return ctx.destroy(targets[0])) \
.and_if_you_do(func(ctx: Evesses.Context, _targets: Variant) -> Result: 
	return ctx.draw(1))
```

If destroy returns `Result.Err`, the entire effect aborts (some effects continue even if they can't do part of their effect)

If destroy returns `ctx.none()` (Option.None), the effect continues but "if you do" fails (correct!).

If destroy returns `ctx.some(event)` (Option.Some), "if you do" succeeds and draws (correct!).

**Result.Err = "can't proceed, abort"**
**Option.None = "proceeded, but nothing happened"**
**Option.Some = "proceeded and did something"**

You need both because they represent different failure modes.

### Can I use Evesses for non-card games?

Absolutely! Evesses is designed to be game-agnostic.

The core concepts map to any game:
- **Direct effects** -> Player actions
- **Triggers** -> Passive abilities, equipment effects
- **Floodgates** -> Buffs, debuffs, environmental effects, modifiers
- **Temporal scopes** -> Your game's time structure (turns, rounds, phases, etc.)

### What's the performance like?

Evesses prioritises correctness over performance. For typical card game usage (10-100 effects per turn), performance is excellent.

For games with thousands of simultaneous effects, you may hit the iteration limit. Adjust with `set_max_chain_iterations()` or restructure your effects to be less granular.

The main performance cost is in:
1. Chain resolution loops (worst case: triggers triggering triggers)
2. Floodgate application (O(n) per floodgate per action)
3. History tracking (grows unbounded - clear periodically if needed)

As always, bench, ID bottlenecks, then optimise. 
If you're having particularly aggregious issues with performance let me know and I'll do something about it.

### Do I need to know Yu-Gi-Oh! to use this?

No! While Evesses is inspired by YGO's effect system, you don't need to know anything about the card game. The core concepts (effects, triggers, floodgates, chains) are generic.

That said, understanding YGO's priority system and chain resolution can help you understand the philosophy behind it. But it is strictly not required, and I would not recommend learning the clusterfuck of a game that is modern YGO.

### How do I debug chain resolution issues?

1. **Check timing history**: `ev.get_timing_history()` shows all events that occurred
2. **Add debug prints** in your actions to see execution order
3. **Check constraint tracker**: Make sure "once per turn" effects are clearing properly
4. **Verify floodgate order**: Floodgates with the same layer apply in insertion order (for now! i'm intending to expose a method to let you sort soon)
5. **Look for infinite loops**: If you hit the iteration limit, you have circular triggers

### Can I save/load Evesses state?

Not yet! :c

Evesses itself is stateless except for:
- `_timing_history` - the event log
- `_constraint_tracker` - once per turn tracking
- `_current_scope_stack` - current temporal position

You can serialize these manually, but Evesses doesn't provide built-in save/load. Your Context implementation holds the actual game state, which you should save separately.

### How do I handle simultaneous triggers?

Use `set_segoc_sorter()` to define custom sorting logic:

```gdscript
ev.set_segoc_sorter(func(triggers: Array) -> Array:
	# Sort by priority, then by timestamp, then by player
	triggers.sort_custom(func(a: Evesses.TriggerEffect, b: Evesses.TriggerEffect) -> bool:
		if a.priority != b.priority:
			return a.priority > b.priority
		return a.timestamp < b.timestamp
	)
	return triggers
)
```

---

## Full Example: Complete Card

```gdscript
# "Dark Hole: Destroy all monsters on the field"
class_name DarkHoleCard
extends Node

var effect: Evesses.Effect

func _ready() -> void:
	var ev: Evesses = get_evesses()  # Magic function that always gets evesses.
	                                  # You might put evesses into an autoload for this, or you might 
	                                  # just use simple dep injection.
	
	effect = ev.direct_effect() \
		.tag("spell") \
		.tag("normal") \
		.action(func(ctx: Evesses.Context, _targets: Variant) -> Result:
			var all_monsters: Array = ctx.world.get_all_monsters()
			return ctx.destroy(all_monsters)) \
		.build()

func activate(ctx: Evesses.Context) -> void:
	var ev: Evesses = get_evesses()
	
	# Activate goes through REQUEST phase (cost, targets, etc)
	var result: Result = ev.activate_effect(effect, ctx)
	if result.is_err():
		print("couldn't activate: ", result.unwrap_err())
		return
	
	# Allow opponent to chain responses if needed
	# (in real game, this would be a response window for the player)
	
	# Resolve the chain (RESOLUTION -> COMMIT for all effects)
	ev.resolve_chain(ctx)
```

---

Now go build your game! And tell me about problems you've had so I may fix them, dammit.
