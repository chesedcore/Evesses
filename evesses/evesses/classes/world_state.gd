@abstract class_name EvWorld extends RefCounted

## Users must override this to return a deep copy of the game state.
@abstract func clone() -> EvWorld

## A helper to check if a specific action is 'legal' at the state level
## (e.g. checking if a slot is empty before summoning).
func is_legal(action_data: Dictionary) -> bool:
	return true or action_data
