"""  
 *	This file is part of the "Receipt Validator SDK" project by FLOBUK.
"""
## Demo implementation for Cross-platform wrapper for real money purchases, as well as for virtual ingame purchases (for virtual currency).
## Initializes the native billing system, handles different store interfaces and integrates their callbacks respectively
class_name RV_IAPManager
extends Node

## Fired when text should be printed to console for debug purposes
signal debug_callback(color: Color, text: String)
## Fired when a purchase finished, delivering result and data
signal purchase_callback(success: bool, data: Variant)

## Available billing stores
enum AppStore {
	UNKNOWN = 0, ## Default for unsupported runtime
	GOOGLE_PLAY = 1, ## Google Play (Android)
	APPLE_APP_STORE = 2, ## Apple App Store (macOS, tvOS, iOS)
}

## Array of ProductDefinition classes that should be initialized on App Stores
@export var product_definitions: Array[RV_ProductDefinition]

## Reference to the billing platform we are running on
var app_store: AppStore = AppStore.UNKNOWN
## Reference to the underlying store system used
var store_system: RV_StoreSystem


func _init() -> void:
	if OS.has_feature("editor"):
		_debug_log(Color.YELLOW, "In-App Purchasing cannot be tested in the Editor.")
		return
	else:
		var runtime_platform: String = OS.get_name()
		match runtime_platform:
			"macOS", "iOS":
				app_store = AppStore.APPLE_APP_STORE
				store_system = RV_AppleAppStore.new()
			"Android":
				app_store = AppStore.GOOGLE_PLAY
				store_system = RV_GooglePlayStore.new()
	
	store_system.on_initialized.connect(_on_initialized)
	store_system.on_initialize_failed.connect(_on_initialize_failed)
	store_system.on_purchased.connect(_on_process_purchase)
	store_system.on_purchase_failed.connect(_on_purchase_failed)
	store_system.on_restore.connect(_on_restore_succeeded)


func _ready() -> void:
	if store_system == null:
		return
	
	for definition in product_definitions:
		store_system.product_definitions[definition.id] = definition
	
	# this initializes the store and requests user inventory from the Receipt Validator immediately
	# if you want to have the user login beforehand you would not do it this way but wait for auth
	store_system.initialize()


## Purchase product based on its product identifier
func purchase(product_id) -> void:
	if store_system == null or store_system.init_state != RV_StoreSystem.InitializationState.INITIALIZED:
		_on_purchase_failed("Billing is not initialized.")
		return
	
	store_system.purchase(product_id)


## Restore already purchased user's transactions for non consumable IAPs.
## If receipt validation is used, the restored receipts are also getting validated again
func restore_transactions() -> void:
	if store_system == null or store_system.init_state != RV_StoreSystem.InitializationState.INITIALIZED:
		_on_purchase_failed("Billing is not initialized.")
		return
	
	store_system.restore_transactions()


func _on_initialized() -> void:
	_debug_log(Color.GREEN, "In-App Purchasing successfully initialized")
	ReceiptValidator.purchase_callback.connect(_on_purchase_result)
	ReceiptValidator.request_inventory()


# this is called from the underlying store system whenever a purchase or restore happens natively
func _on_process_purchase(product_id: String, is_new: bool = true) -> void:
	var definition: RV_ProductDefinition = store_system.product_definitions[product_id]
	
	# do validation, the magic happens here!
	var state: RV_ReceiptValidator.PurchaseState = ReceiptValidator.request_purchase(definition);
	
	# handle what happens with the product next
	match (state):
		RV_ReceiptValidator.PurchaseState.Purchased:
			# nothing to do here: with the transaction finished at this point it means that either
			# 1) the product is already active in the user's inventory (e.g. on a restore), or
			# 2) validation is not supported at all, e.g. when running on a non-supported store
			_debug_log(Color.WHITE, "Product '" + definition.id + "' is already purchased.");
			
		RV_ReceiptValidator.PurchaseState.Pending:
			# transaction is pending or about to be validated on the server
			# the ReceiptValidator will fire its purchaseCallback when done processing
			_debug_log(Color.WHITE, "Product purchase '" + definition.id + "' is pending.");
			return
			
		RV_ReceiptValidator.PurchaseState.Failed:
			# transaction invalid or failed. Complete it to skip further validation attempts
			_debug_log(Color.RED, "Product purchase: '" + definition.id + "' deemed as invalid.")
			
	# with the transaction finished (without validation) or failed, just call our purchase handler. 
	# we just hand over the product id to keep the expected dictionary structure consistent
	var resultData: Dictionary = {"data": {"productId": definition.id}};
	_on_purchase_result(state == RV_ReceiptValidator.PurchaseState.Purchased, resultData);


func _on_initialize_failed(error: String) -> void:
	_debug_log(Color.RED, "In-App Purchasing initialize failed: " + error)


func _on_purchase_failed(error: String) -> void:
	_debug_log(Color.RED, "Purchase failed: " + error)
	purchase_callback.emit(false, null)


# you would do your custom purchase handling by subscribing to the purchase_callback signal
# for example when not making use of user inventory, save the purchase on device for offline mode
# unlock the reward in your UI, activate something for the user, or anything else you want it to do!
# since purchase callbacks can happen or complete anywhere, your purchase handler should also be
# present in every scene or be added as an autoload as well
func _on_purchase_result(success: bool, data: Dictionary) -> void:
	purchase_callback.emit(success, data)


func _on_restore_succeeded(result: bool) -> void:
	_debug_log(Color.WHITE, "Restore transactions finished, success: " + str(result))


func _debug_log(color: Color, text: String) -> void:
	debug_callback.emit(color, text)
