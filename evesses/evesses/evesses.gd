class_name Evesses extends RefCounted

enum PayloadType {
	REQUEST,      #proposed effect (cost, payload and constraint)
	RESOLUTION,   #post-floodgate, partially processed
	DIRECTIVE,    #fully processed, must execute
	TIMING        #historical marker only
}

class Event:
	var id: int
	var payload_type: PayloadType
	var tags: Array[String] = []
	var cause: Cause
	var cost: Callable
	var payload: Callable
	var timestamp: int
	
	func _init(p_type: PayloadType, p_payload: Callable) -> void:
		payload_type = p_type
		payload = p_payload
		timestamp = Time.get_ticks_msec()
		id = _generate_id()
	
	static var _next_id: int = 0
	static func _generate_id() -> int:
		_next_id += 1
		return _next_id

class Cause:
	var source: Object
	var reason: String
	var extra: Dictionary = {}
	
	func _init(p_source: Object, p_reason: String) -> void:
		source = p_source
		reason = p_reason
