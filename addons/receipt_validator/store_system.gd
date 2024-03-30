"""  
 *	This file is part of the "Receipt Validator SDK" project by FLOBUK.
"""
## Interface for the implementation of a native or external billing system.
## Provides definition of base classes around initializing and purchasing
class_name RV_StoreSystem
extends Node

## Fired when billing initialization completes
signal on_initialized
## Fired when billing initialization fails, providing error text
signal on_initialize_failed(error: String)
## Fired when a purchase completes, delivering its product ID and whether it is a new purchase
signal on_purchased(product_id: String, new: bool)
## Fired when a purchase is in pending/deferred status, delivering its product id
signal on_purchase_pending(product_id: String)
## Fired when a purchase fails, providing error text
signal on_purchase_failed(error: String)
## Fired when a restore transactions workflow completes, delivering its state
signal on_restore(state: bool)

## Different billing system initialization states
enum InitializationState {
	UNKNOWN, ## Default at not yet initialized
	CONNECTING, ## Connecting to the corresponding billing system
	GET_PRODUCTS, ## Getting product meta data from the App Store
	GET_PURCHASES, ## Getting previous purchases from the App Store
	INITIALIZED, ## Billing system ready for handling purchases
}

## Singleton access to the native billing class and methods
var billing
## Current billing system initialization state
var init_state: InitializationState = InitializationState.UNKNOWN
## Dictionary with the products that should be requested from the store
var product_definitions: Dictionary
## Dictionary containing the purchased products with their store data
var purchase_dic: Dictionary


## Implementing follow up logic on intialization
func initialize() -> void:
	pass

## Fetching meta data about App Store products
func fetch_products() -> void:
	pass

## Initiating a purchase with the App Store
func purchase(product_id: String) -> void:
	pass

## Returning whether a product was returned as bought or not
func is_purchased(product_id: String) -> bool:
	return false

## Consuming or acknowledging a successful purchase
func finish_transaction(product_id: String) -> void:
	pass

## Invoking the restore transactions workflow
func restore_transactions() -> void:
	pass
