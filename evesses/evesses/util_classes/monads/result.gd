##a struct representing a value that is either OK or an Err
@tool
class_name Result extends Monad

##the value inside the struct. [code]_value[/code] is the only avenue of unsafe access.
@export var _value: Variant
##determines if this struct has a valid value (Ok) or an en error(Err)
@export var _is_ok: bool

##piss basic factory
static func from(value: Variant = null, ok_or_not: bool = true) -> Result:
	var res := new()
	res._value = value
	res._is_ok = ok_or_not
	return res

##factory that guarantees an Ok
static func ok(value: Variant) -> Result:
	return Result.from(value, true)

##factory that guarantees an Err
static func err(error: Variant) -> Result:
	return Result.from(error, false)

##factory that guarantees an Ok(()) (a null Ok where the Ok val doesn't matter) 
static func ok_as_is() -> Result:
	return Result.ok(null)

##checks if ok, does what it says on the tin
func is_ok() -> bool:
	return _is_ok

##do you seriously need explaining
func is_err() -> bool:
	return not _is_ok

##explodes if the accessed value is an Err. otherwise returns the value.
func unwrap() -> Variant:
	assert(_is_ok, "Called unwrap() on an Err value: " + str(_value))
	return _value

##explodes if the accessed value is an Ok(!!), returns the wrapped Err
func unwrap_err() -> Variant:
	assert(not _is_ok, "Called unwrap_err() on an ok value")
	return _value

##like unwrap, but prints another message if it explodes
func expect(msg: String) -> Variant:
	assert(_is_ok, msg + ": " + str(_value))
	return _value

##returns either the Ok value or the given default (if Err)
func unwrap_or(default: Variant) -> Variant:
	return _value if _is_ok else default

##returns either the Ok value or the closure's return (if Err)
func unwrap_or_else(fallback: Callable) -> Variant:
	return _value if _is_ok else fallback.call(_value)

##just calls the function on the value if ok, wraps result back in ok
func map(func_: Callable) -> Result:
	if _is_ok:
		return Result.ok(func_.call(_value))
	return self

##an alias for map. not naming it this is a missed opportunity
func ok_and(func_: Callable) -> Result:
	return map(func_)

##same as map but for errors
func map_err(func_: Callable) -> Result:
	if not _is_ok:
		return Result.err(func_.call(_value))
	return self

##like map but the function itself returns a Result, so we don't double wrap
func and_then(func_: Callable) -> Result:
	if _is_ok:
		return func_.call(_value)
	return self

##basically and_then but for the error case
func or_else(func_: Callable) -> Result:
	if not _is_ok:
		return func_.call(_value)
	return self

##pattern match style, just call one function or the other depending on state
func match_result(on_ok: Callable, on_err: Callable) -> Variant:
	if _is_ok:
		return on_ok.call(_value)
	else:
		return on_err.call(_value)

func _to_string() -> String:
	if _is_ok:
		return "Result::Ok(%s)" % str(_value)
	else:
		return "Result::Err(%s)" % str(_value)
