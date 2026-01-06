class_name Monad extends RefCounted

func match_monad(if_option: Callable, if_result: Callable) -> Variant:
	var this: Monad = self
	if this is Option:
		return if_option.call(this)
	elif this is Result:
		return if_result.call(this)
	return Option.none()

static func wrap_cast(val: Variant, aggressive: bool = false) -> Monad:
	if val == null: return Option.none()
	if val is Monad: return val
	if aggressive and not val: return Result.err(val)
	return Option.some(val)
