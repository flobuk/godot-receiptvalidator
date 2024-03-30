"""  
 *	This file is part of the "Receipt Validator SDK" project by FLOBUK.
"""
## Implementation of the InAppStore billing library for the Apple App Store
class_name RV_AppleAppStore
extends RV_StoreSystem

## Matches SKPaymentTransaction.SKPaymentTransactionState in the StoreKit Library
enum PurchaseState {
	PURCHASING,
	PURCHASED,
	FAILED,
	RESTORED,
	DEFERRED,
}


func _init() -> void:
	if Engine.has_singleton("InAppStore"):
		billing = Engine.get_singleton("InAppStore")
		billing.set_auto_finish_transaction(false)
		init_state = InitializationState.CONNECTING


## Starts or continues the next initialization step.
## Does nothing if the initialization has been finished already
func initialize() -> void:
	if not Engine.has_singleton("InAppStore"):
		print_debug("Apple IAP support is not enabled. Please see the setup instructions.")
		return

	if init_state == InitializationState.CONNECTING:
		init_state = InitializationState.GET_PRODUCTS
		_check_events()
	
	match init_state:
		InitializationState.INITIALIZED:
			print_debug("IAP billing already initialized.")
			return
		InitializationState.GET_PRODUCTS:
			fetch_products()


## Fetch product meta information
func fetch_products() -> void:
	var result = billing.request_product_info({ "product_ids": product_definitions.keys() })
	if result != OK:
		print_debug("error requesting product details from app store")


## Bring up the native purchase popup for the product identifier specified
func purchase(product_id: String) -> void:
	var result = billing.purchase({ "product_id": product_id })
	if result != OK:
		on_purchase_failed.emit("error purchasing item")


## Checks whether a product is included in the purchase dictionary.
## The product needs to be in the PurchaseState.PURCHASED or RESTORED state
func is_purchased(product_id: String) -> bool:
	if (purchase_dic.has(product_id)
			and (purchase_dic[product_id].type_code == PurchaseState.PURCHASED
			or purchase_dic[product_id].type_code == PurchaseState.RESTORED)):
		return true
	return false


## Calls into StoreKit for initiating the restore transactions workflow
func restore_transactions() -> void:
	billing.restore_purchases()


## Mark the transaction as finished with the billing system
func finish_transaction(product_id: String) -> void:
	billing.finish_transaction(product_id)


func _check_events() -> void:
	while true:
		await ReceiptValidator.get_tree().create_timer(2).timeout
		if billing.get_pending_event_count() > 0:
			
			var events: Array
			while billing.get_pending_event_count() > 0:
				var event = billing.pop_pending_event()
				events.append(event)
				
				# the product definition does not exist yet, for example
				# "purchase" event fired before "product_info", or deleted product
				# create it and add it to the Dictionary with only necessary properties
				if "product_id" in event and not product_definitions.has(event.product_id):
					var product_definition: RV_ProductDefinition = RV_ProductDefinition.new()
					product_definition.id = event.product_id
					product_definition.type = RV_ProductDefinition.ProductType.NON_CONSUMABLE
					product_definitions[event.product_id] = product_definition
			
			events.reverse()
			for event in events:
				match event.type:
					"product_info":
						if event.result == "ok":
							for i in event.ids.size():
								var product_definition := RV_ProductDefinition.new().from_apple_app_store(event, i)
								product_definitions[product_definition.id] = product_definition
							
							init_state = InitializationState.INITIALIZED
							on_initialized.emit()
							
					"purchase":
						if event.result == "progress":
							continue
						
						if event.result == "ok":
							purchase_dic[event.product_id] = event

							match event.type_code:
								PurchaseState.DEFERRED:
									on_purchase_pending.emit(event.product_id)
								PurchaseState.PURCHASED, PurchaseState.RESTORED:
									if (product_definitions[event.product_id].type != RV_ProductDefinition.ProductType.CONSUMABLE
										and product_definitions[event.product_id].has_receipt()):
										continue
									
									product_definitions[event.product_id].receipt = event.transaction_id
									on_purchased.emit(event.product_id, true)
						else:
							on_purchase_failed.emit("error purchasing item")
							
					"restore":
						match event.result:
							#"ok": event.type purchase is fired after this with same products, not sure if bug
								#purchase_dic[event.product_id] = event
								#product_definitions[event.product_id].receipt = event.transaction_id
							"completed":
								on_restore.emit(true)
							"error", "unhandled":
								on_restore.emit(false)
