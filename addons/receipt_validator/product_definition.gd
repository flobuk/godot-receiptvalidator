"""  
 *	This file is part of the "Receipt Validator SDK" project by FLOBUK.
"""
## Product definition that is populated with data from the App Stores
## after the store system initialized and received all product meta information
class_name RV_ProductDefinition
extends Resource

## Product type that defines further logic
enum ProductType {
	CONSUMABLE, ## Consumables are getting consumed at some point
	NON_CONSUMABLE, ## Non-Consumables exist forever when owned once
	SUBSCRIPTION, ## Subscriptions expire after their duration
}

## Global product identifier
@export var id: String
## Product type
@export var type: ProductType = ProductType.CONSUMABLE
## Transaction ID if the product is owned
var receipt: String


## Converts data from Google Play response
func from_google_play(definition) -> RV_ProductDefinition:
	id = definition["sku"]
	
	# this is needed for a type comparison and validation request
	for product in IAPManager.product_definitions:
		if id == product.id:
			type = product.type
			break
	
	return self


## Converts data from Apple App Store response
func from_apple_app_store(definitions, index: int) -> RV_ProductDefinition:
	id = definitions.ids[index]
	
	# this is needed for a type comparison and validation request
	for product in IAPManager.product_definitions:
		if id == product.id:
			type = product.type
			break
	
	return self


## Returns whether the receipt field is empty or not
func has_receipt() -> bool:
	return receipt != null && receipt != String()
