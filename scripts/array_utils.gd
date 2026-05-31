# NodeUtils.gd
class_name ArrayUtils

static func find(arr : Array, id : int) -> int:
	var idx = arr.find_custom(
	func(c):
		return c.id == id
	)
	return idx
