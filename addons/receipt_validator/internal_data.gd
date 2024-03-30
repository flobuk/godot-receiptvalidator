"""  
 *	This file is part of the "Receipt Validator SDK" project by FLOBUK.
"""
## Resource holding all internal addon data
class_name RV_InternalData
extends Resource

@export var data: Dictionary


func has(key: String) -> bool:
	return data.has(key)


func get_data(key: String) -> Variant:
	if not has(key):
		return null
	
	return data[key]


func set_data(key: String, value: Variant) -> void:
	data[key] = value


func remove(key: String) -> void:
	if not has(key):
		return
	
	data.erase(key)


func save(path: String) -> void:
	ResourceSaver.save(self, path)
