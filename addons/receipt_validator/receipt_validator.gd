"""  
 *	This file is part of the "Receipt Validator SDK" project by FLOBUK.
"""
## Server-side, remote receipt validation via Receipt Validator service (https://flobuk.com/validator).
## Supports getting user inventory from cloud storage to not only rely on local purchase data
class_name RV_ReceiptValidator
extends Node

## Fired when the User Inventory is returned successfully
signal inventory_callback
## Fired when a non-pending validation finishes, successful or not
signal purchase_callback(success, response)

## Available types for requesting User Inventory
enum InventoryRequestType {
	DISABLED, ## No request will be made
	MANUAL, ## Only on manual method call
	ONCE, ## Automatic on initialization
	DELAY, ## Rate-limited within 30 minutes (default)
}

## State of the purchase returned from validation
enum PurchaseState {
	Purchased,
	Pending,
	Failed
}

## HTTPS endpoint for receipt validation. Do not change!
const VALIDATION_ENDPOINT: String = "https://flobuk.com/validator/dev/receipt/"
## HTTPS endpoint for requesting user inventory. Do not change!
const USER_ENDPOINT: String = "https://flobuk.com/validator/dev/user/"
## Key for saving last requested inventory timestamp within player data
const LAST_INV_TIMESTAMP_KEY: String = "fbrv_inventory_timestamp"
## Location of where internal data file should be saved on the device
const DATA_PATH: String = "user://receipt_validator/internal.tscn"

## Your application endpoint ID on the service
@export var app_id: String

## Application bundle identifier for Google Play.
@export var bid_android: String
## Application bundle identifier for Apple App Store.
@export var bid_ios: String

## User Inventory is not supported on the FREE plan.
## Please leave it on 'DISABLED' if you didn't upgrade
@export var inv_request_type: InventoryRequestType = InventoryRequestType.DISABLED
## The unique user ID for that inventory should be requested for
@export var user_id: String

var _inventory: Dictionary
var _last_inv_time: float = -1
var _inv_req_active: bool = false
var _inv_delay: int = 1800
var _internal_data: RV_InternalData


func _init() -> void:
	if _internal_data == null and ResourceLoader.exists(DATA_PATH):
		_internal_data = ResourceLoader.load(DATA_PATH) as RV_InternalData
		return

	_internal_data = RV_InternalData.new()
	_internal_data.save(DATA_PATH)


## Request inventory from the server, for the user specified as 'user_id'
## Billing has to be initialized at this point else no request will be made
func request_inventory() -> void:
	if not can_request_inventory():
		print("Receipt Validator: CanRequestInventory returned false.")
		return
	
	if not _is_server_validation_supported():
		print("Receipt Validator: Inventory Request not supported.")
		return
	
	if not _has_active_receipt() and not _has_purchase_history():
		print("Receipt Validator: Inventory Request not necessary.")
		return
	
	_inv_req_active = true
	create_inventory_request()


## Returns whether a User Inventory request can be made based on the selected request type
func can_request_inventory() -> bool:
	if _inv_req_active:
		return false
	
	match inv_request_type:
		InventoryRequestType.DISABLED:
			return false
		InventoryRequestType.ONCE:
			if _last_inv_time > 0:
				return false
		InventoryRequestType.DELAY:
			if (_last_inv_time > 0
					and (Time.get_unix_time_from_system() - _last_inv_time) < _inv_delay):
				return false
	
	if user_id == String():
		return false
	
	return true


## Return current user inventory stored in memory
func get_inventory() -> Dictionary:
	return _inventory


func request_purchase(definition: RV_ProductDefinition) -> PurchaseState:
	if not definition.has_receipt():
		return PurchaseState.Failed
	
	if inv_request_type != InventoryRequestType.DISABLED and _is_purchased(definition.id):
		return PurchaseState.Purchased
	
	if _is_server_validation_supported():
		create_purchase_request(definition)
		return PurchaseState.Pending
	
	return PurchaseState.Purchased


## Creates the HTTP request on User Inventory, handled internally
func create_inventory_request() -> void:
	var http_req: HTTPRequest = HTTPRequest.new()
	var url: String = USER_ENDPOINT + app_id + "/" + user_id
	var headers: Array[String] = ["Content-Type: application/json"]
	add_child(http_req)
	
	http_req.request_completed.connect(_inventory_request_completed)
	var result: Error = http_req.request(url, headers, HTTPClient.METHOD_GET)
	if result != OK:
		push_error("An error occurred while creating the HTTP create_inventory_request.")


func _inventory_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print_debug("Inventory HTTP request did not receive a valid server response.")
		return
	
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		print_debug("Inventory HTTP request response could not be parsed into JSON format.")
		return
	
	var purchases: Array = json.get_data()["purchases"]
	_inventory.clear()
	
	for purchase in purchases:
		var response: PurchaseResponse = PurchaseResponse.new().from_dic(purchase["data"])
		_inventory[response.product_id] = response
	
	_last_inv_time = Time.get_unix_time_from_system()
	_inv_req_active = false
	_set_purchase_history()
	inventory_callback.emit()


## Creates the HTTP request on receipt validation, handled internally
func create_purchase_request(definition: RV_ProductDefinition) -> void:
	var request: ReceiptRequest = ReceiptRequest.new()
	request.pid = definition.id
	request.user = user_id
	request.type = get_type_string(definition.type)
	request.receipt = definition.receipt
	
	match IAPManager.app_store:
		RV_IAPManager.AppStore.GOOGLE_PLAY:
			request.store = "GooglePlay"
			request.bid = bid_android
		RV_IAPManager.AppStore.APPLE_APP_STORE:
			request.store = "AppleAppStore"
			request.bid = bid_ios
	
	var post_data: String = JSON.stringify(request.to_dic())
	var http_req: HTTPRequest = HTTPRequest.new()
	var url: String = VALIDATION_ENDPOINT + app_id
	var headers: Array[String] = ["Content-Type: application/json"]
	add_child(http_req)
	
	#print(post_data)

	http_req.request_completed.connect(_purchase_request_completed.bind(definition.id))
	var result: Error = http_req.request(url, headers, HTTPClient.METHOD_POST, post_data)
	if result != OK:
		push_error("An error occurred while creating the HTTP create_purchase_request.")
		return


func _purchase_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, product_id: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print_debug("Purchase HTTP request did not receive a valid server response.")
		return
	
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		print_debug("Purchase HTTP request response could not be parsed into JSON format.")
		print_debug(body.get_string_from_utf8())
		purchase_callback.emit(false, body.get_string_from_utf8());
		return
	
	var purchase: Dictionary = json.get_data()
	var success: bool = not purchase.has("error") and purchase.has("data")
	
	if success:
		var response: PurchaseResponse = PurchaseResponse.new().from_dic(purchase["data"])
		
		if user_id == String() and purchase.has("user"):
			user_id = purchase["user"];
		
		_inventory[product_id] = response
	
	if purchase == null or purchase.has("error") and purchase["code"] == 10130:
		return

	IAPManager.store_system.finish_transaction(product_id)
	purchase_callback.emit(success, purchase);


func _is_purchased(product_id: String) -> bool:
	if IAPManager.store_system == null:
		return false
	
	if inv_request_type == InventoryRequestType.DISABLED:
		return IAPManager.store_system.product_definitions[product_id].has_receipt()
	
	var purchase_states: Array[int] = [ 0, 1, 4 ]
	if _inventory.has(product_id) and purchase_states.count(_inventory[product_id].status) > 0:
		return true
	
	return false


func _has_purchase_history() -> bool:
	if not _internal_data.has(LAST_INV_TIMESTAMP_KEY):
		return false

	var last_timestamp: float = float(_internal_data.get_data(LAST_INV_TIMESTAMP_KEY))
	var timestamp_now: float = float(Time.get_unix_time_from_system())

	# 2628000 seconds = 1 month
	if (timestamp_now - last_timestamp) < 2628000:
		return true

	_internal_data.remove(LAST_INV_TIMESTAMP_KEY);
	return false


func _has_active_receipt() -> bool:
	var has_receipt: bool = false
	
	match IAPManager.app_store:
		IAPManager.AppStore.GOOGLE_PLAY:
			for definition in IAPManager.store_system.product_definitions.values():
				if (definition.type != RV_ProductDefinition.ProductType.CONSUMABLE
						and definition.has_receipt()):
					has_receipt = true
					break
		IAPManager.AppStore.APPLE_APP_STORE:
			# we are unable to query any local receipts since none are returned automatically on launch
			for definition in IAPManager.store_system.product_definitions.values():
				if definition.type != RV_ProductDefinition.ProductType.CONSUMABLE:
					has_receipt = true
					break
	
	return has_receipt


func _set_purchase_history() -> void:
	if _internal_data.has(LAST_INV_TIMESTAMP_KEY) and _inventory.size() == 0:
		_internal_data.remove(LAST_INV_TIMESTAMP_KEY)
		return
	
	if not _internal_data.has(LAST_INV_TIMESTAMP_KEY) and _inventory.size() > 0:
		_internal_data.set_data(LAST_INV_TIMESTAMP_KEY, _last_inv_time) 


func _is_server_validation_supported() -> bool:
	if IAPManager.app_store == IAPManager.AppStore.UNKNOWN:
		return false
	
	if (IAPManager.store_system == null
		or not IAPManager.store_system.init_state == RV_StoreSystem.InitializationState.INITIALIZED):
		return false
	
	if ((IAPManager.app_store == IAPManager.AppStore.APPLE_APP_STORE and not bid_ios == String())
		or (IAPManager.app_store == IAPManager.AppStore.GOOGLE_PLAY and not bid_android == String())):
		return true

	return false


## Converts the product type received to the expected String format
func get_type_string(type: RV_ProductDefinition.ProductType) -> String:
	match(type):
		RV_ProductDefinition.ProductType.CONSUMABLE:
			return "Consumable"
		RV_ProductDefinition.ProductType.SUBSCRIPTION:
			return "Subscription"
		_:
			return "Non-Consumable"


class ReceiptRequest:
	var store: String
	var bid: String
	var pid: String
	var type: String
	var user: String
	var receipt: String

	func to_dic() -> Dictionary:
		var dic: Dictionary = {}
		dic["store"] = store
		dic["bid"] = bid
		dic["pid"] = pid
		dic["type"] = type
		dic["user"] = user
		dic["receipt"] = receipt
		return dic


class PurchaseResponse:
	var type: String
	var product_id: String
	var sandbox: bool
	var status: int
	var expires_date: int
	var auto_renew: bool
	var billing_retry: bool
	
	func to_dic() -> Dictionary:
		var dic: Dictionary = {}
		dic["type"] = type
		dic["product_id"] = product_id
		dic["sandbox"] = sandbox
		dic["status"] = status
		dic["expires_date"] = expires_date
		dic["auto_renew"] = auto_renew
		dic["billing_retry"] = billing_retry
		return dic
	
	func from_dic(data) -> PurchaseResponse:
		type = data["type"]
		product_id = data["productId"]
		sandbox = data["sandbox"]

		if data.has("status"): status = data["status"]
		if data.has("expiresDate"): expires_date = data["expiresDate"]
		if data.has("autoRenew"): auto_renew = data["autoRenew"]
		if data.has("billingRetry"): billing_retry = data["billingRetry"]
		return self
