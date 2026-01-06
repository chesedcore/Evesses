class_name EvEvent extends RefCounted

enum Kind {
	REQUEST,
	RESOLUTION,
	DIRECTIVE,
	TIMING,
}

var name: String = ""
var kind := Kind.REQUEST
var tags: PackedStringArray
var payload: Variant

static func create(with_name: String) -> EvEvent:
	var ev := new()
	ev.name = with_name
	return ev

func typed_to(enum_kind: Kind) -> EvEvent:
	kind = enum_kind
	return self

func with_tags(arr: Array[String]) -> EvEvent:
	tags = PackedStringArray(arr)
	return self

func with_payload(pl: Variant) -> EvEvent:
	payload = pl
	return self
