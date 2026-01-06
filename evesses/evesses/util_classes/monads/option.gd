##a struct representing a value that either exists (Some) or doesn't (None)
class_name Option extends Monad

##the value inside the struct. [code]_value[/code] is the only avenue of unsafe access.
@export var _value: Variant
##determines if this struct has a value (Some) or is empty (None)
@export var _is_some: bool

##piss basic factory
static func from(value: Variant = null, is_some_or_not: bool = false) -> Option:
	var opt := new()
	opt._value = value
	opt._is_some = is_some_or_not
	return opt

##factory that guarantees a Some
static func some(value: Variant) -> Option:
	return Option.from(value, true)
##factory that guarantees a None
static func none() -> Option:
	return Option.from(null, false)

##checks if some, does what it says on the tin
func is_some() -> bool:
	return _is_some
##do you seriously need explaining
func is_none() -> bool:
	return not _is_some

##explodes if the accessed value is None. otherwise returns the value.
func unwrap() -> Variant:
	assert(_is_some, "Called unwrap() on a None value")
	return _value
##like unwrap, but prints another message if it explodes
func expect(msg: String) -> Variant:
	assert(_is_some, msg)
	return _value

##returns either the Some value or the given default (if None)
func unwrap_or(default: Variant) -> Variant:
	return _value if _is_some else default
##returns either the Some value or the closure's return (if None)
func unwrap_or_else(fallback: Callable) -> Variant:
	return _value if _is_some else fallback.call()

##just calls the function on the value if some, wraps result back in some
func map(func_: Callable) -> Option:
	if _is_some:
		return Option.some(func_.call(_value))
	return self
##like map but the function itself returns an Option, so we don't double wrap
func and_then(func_: Callable) -> Option:
	if _is_some:
		return func_.call(_value)
	return self

##returns this option if some, otherwise returns the other option
func or_option(other: Option) -> Option:
	return self if _is_some else other
##returns this option if some, otherwise calls the function to get a fallback option
func or_else(fallback: Callable) -> Option:
	return self if _is_some else fallback.call()
##pattern match style, just call one function or the other depending on state
func match_option(on_some: Callable, on_none: Callable) -> Variant:
	if _is_some:
		return on_some.call(_value)
	else:
		return on_none.call()
##converts this option into a result, using the given error if none
func ok_or(error: Variant) -> Result:
	if _is_some:
		return Result.ok(_value)
	return Result.err(error)
##converts this option into a result, calling the error function if none
func ok_or_else(error_fn: Callable) -> Result:
	if _is_some:
		return Result.ok(_value)
	return Result.err(error_fn.call())
##replaces the value inside if some, does nothing if none
func replace(value: Variant) -> Option:
	if _is_some:
		_value = value
	return self
##takes the value out, leaving None behind
func take() -> Option:
	if _is_some:
		var val = _value
		_value = null
		_is_some = false
		return Option.some(val)
	return Option.none()
func _to_string() -> String:
	if _is_some:
		return "Option::Some(%s)" % str(_value)
	else:
		return "Option::None"
