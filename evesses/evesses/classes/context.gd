# ev_context.gd
class_name EvContext
extends RefCounted

var source: Node
var targets: Array[Node] = []
var value: Variant
var tags: Array[String] = []
var result: Result # From the Godot-Optional library
