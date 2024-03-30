"""  
 *	This file is part of the "Receipt Validator SDK" project by FLOBUK.
"""
## Implementation of the GodotGooglePlayBilling billing library for Google Play
class_name RV_GooglePlayStore
extends RV_StoreSystem

## Matches Purchase.PurchaseState in the Play Billing Library
enum PurchaseState {
	UNSPECIFIED,
	PURCHASED,
	PENDING,
}

var _product_details_query_timer: SceneTreeTimer = null
var _purchases_query_timer: SceneTreeTimer = null


func _init() -> void:
	if Engine.has_singleton("GodotGooglePlayBilling"):
		billing = Engine.get_singleton("GodotGooglePlayBilling")
		
		billing.connected.connect(_on_connected) # No params
		billing.disconnected.connect(_on_disconnected) # No params
		billing.connect_error.connect(_on_connect_error) # Response ID (int), Debug message (string)
		billing.query_purchases_response.connect(_on_purchases_query) # Purchases (Dictionary[])
			
		billing.purchases_updated.connect(_on_purchase_updated) # Purchases (Dictionary[])
		billing.purchase_error.connect(_on_purchase_error) # Response ID (int), Debug message (string)
		billing.sku_details_query_completed.connect(_on_product_details_query) # SKUs (Dictionary[])
		billing.sku_details_query_error.connect(_on_product_details_query_error) # Response ID (int), Debug message (string), Queried SKUs (string[])
		init_state = InitializationState.CONNECTING


## Starts or continues the next initialization step.
## Does nothing if the initialization has been finished already
func initialize() -> void:
	if not Engine.has_singleton("GodotGooglePlayBilling"):
		print("Android IAP support is not enabled. Please see the setup instructions.")
		return
	
	match init_state:
		InitializationState.INITIALIZED:
			print_debug("IAP billing already initialized.")
			return
		InitializationState.CONNECTING:
			billing.startConnection()
		InitializationState.GET_PRODUCTS:
			fetch_products()
		InitializationState.GET_PURCHASES:
			restore_transactions()


func _on_connected() -> void:
	init_state = InitializationState.GET_PRODUCTS
	fetch_products()


func _on_disconnected() -> void:
	on_initialize_failed.emit("Billing disconnected.")


func _on_connect_error(response_id, error_message) -> void:
	on_initialize_failed.emit("Billing error: " + error_message)


## Fetch product meta information.
## This means two calls, for in-app products and subscriptions individually
func fetch_products() -> void:
	billing.querySkuDetails(product_definitions.keys(), "inapp")
	billing.querySkuDetails(product_definitions.keys(), "subs")


func _on_product_details_query(product_infos) -> void:
	for p_info in product_infos:
		var definition := RV_ProductDefinition.new().from_google_play(p_info)
		product_definitions[definition.id] = definition
	
	if _product_details_query_timer == null:
		_product_details_query_timer = ReceiptValidator.get_tree().create_timer(2)
		await _product_details_query_timer.timeout
		_product_details_query_timer = null
		
		init_state = InitializationState.GET_PURCHASES
		restore_transactions()


func _on_product_details_query_error(response_id, error_message, products_queried) -> void:
	_on_connect_error(response_id, error_message)


## Bring up the native purchase popup for the product identifier specified
func purchase(store_id: String) -> void:
	var result = billing.purchase(store_id)
	if result.status != OK:
		on_purchase_failed.emit("error purchasing item")


## Checks whether a product is included in the purchase dictionary.
## The product needs to be in the PurchaseState.PURCHASED state
func is_purchased(store_id: String) -> bool:
	if (purchase_dic.has(store_id)
			and purchase_dic[store_id].purchase_state == PurchaseState.PURCHASED):
		return true
	return false


## Fetch purchased products.
## This means two calls, for in-app products and subscriptions individually
func restore_transactions() -> void:
	billing.queryPurchases("inapp")
	billing.queryPurchases("subs")


func _on_purchase_updated(purchases) -> void:
	for purchase in purchases:
		purchase_dic[purchase.sku] = purchase

		match purchase.purchase_state:
			PurchaseState.PENDING:
				on_purchase_pending.emit(purchase.sku)
			PurchaseState.PURCHASED:
				product_definitions[purchase.sku].receipt = purchase.purchase_token
				# do not fire on_purchased signal during restore transactions at initialization
				# the user will then have to press the restore button in-game to claim all purchases
				if init_state == InitializationState.INITIALIZED:
					on_purchased.emit(purchase.sku, !purchase.is_acknowledged)
			#PurchaseState.UNSPECIFIED do nothing


func _on_purchase_error(response_id, error_message) -> void:
	on_purchase_failed.emit("purchase error: " + error_message)


func _on_purchases_query(result):
	if result.status != OK:
		_on_connect_error(result.response_code, result.debug_message)
		return
	
	_on_purchase_updated(result.purchases)
	
	if _purchases_query_timer == null:
		_purchases_query_timer = ReceiptValidator.get_tree().create_timer(2)
		await _purchases_query_timer.timeout
		_purchases_query_timer = null
	
	if init_state != InitializationState.INITIALIZED:
		init_state = InitializationState.INITIALIZED
		on_initialized.emit()
	else:
		on_restore.emit(true)


func _on_purchase_acknowledged(purchase_token: String) -> void:
	for purchase in purchase_dic.values():
		if purchase.purchase_token == purchase_token:
			on_purchased.emit(purchase.sku)


func _on_purchase_acknowledged_error(response_id, error_message, purchase_token) -> void:
	on_purchase_failed.emit("acknowledge error: " + error_message)


func _on_purchase_consumed(purchase_token: String) -> void:
	for purchase in purchase_dic.values():
		if purchase.purchase_token == purchase_token:
			on_purchased.emit(purchase.sku)


func _on_purchase_consumed_error(response_id, error_message, purchase_token) -> void:
	on_purchase_failed.emit("consume error: " + error_message)


## Mark the transaction as finished with the billing system.
## For a consumable product this means consuming it, else transaction acknowledgement
func finish_transaction(product_id: String) -> void:
	var definition: RV_ProductDefinition = product_definitions[product_id]
	var purchase = purchase_dic[definition.id]

	if definition.type == RV_ProductDefinition.ProductType.CONSUMABLE:
		billing.consumePurchase(purchase.purchase_token)
	elif not purchase.is_acknowledged:
		billing.acknowledgePurchase(purchase.purchase_token)
