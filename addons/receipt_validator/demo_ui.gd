"""  
 *	This file is part of the "Receipt Validator SDK" project by FLOBUK.
"""
## UI Script for demo purposes
class_name RV_DemoUI
extends Control

## Node showing that the product was bought
@export var non_consumable_flag: Control
## Node showing that the product was bought
@export var subscription_flag: Control

## Console view
@export var log_window: Control
## Display of system and server messages
@export var log_text: RichTextLabel
## Notice when running in the editor
@export var editor_text: Control
## Feedback window
@export var info_window: Control
## Message inside feedback window
@export var info_text: Label

## Count of currently processing orders
var _processingPurchasesCount: int


func _ready() -> void:
	if not OS.has_feature("editor"):
		editor_text.hide()
	
	# subscribe to callbacks
	ReceiptValidator.inventory_callback.connect(_inventory_retrieved)
	IAPManager.purchase_callback.connect(_purchase_result)
	IAPManager.debug_callback.connect(_print_message)

	_update_ui()


# inventory callback
func _inventory_retrieved() -> void:
	_print_message(Color.GREEN, "Inventory retrieved.")
	
	var inventory: Dictionary = ReceiptValidator.get_inventory()
	for productID in inventory.keys():
		_print_message(Color.WHITE, JSON.stringify(inventory[productID].to_dic()))
		
	_update_ui()


# buy buttons for different product types
func buy_consumable() -> void:
	buy(IAPManager.product_definitions[0].id)

func buy_non_consumable() -> void:
	buy(IAPManager.product_definitions[1].id)

func buy_subscription() -> void:
	buy(IAPManager.product_definitions[2].id);


# buy method triggering billing system
func buy(product_id: String) -> void:
	_processingPurchasesCount += 1
	_print_message(Color.WHITE, "Purchase Processing Count: " + str(_processingPurchasesCount))
	_update_ui()
	
	IAPManager.purchase(product_id)


# forward restore attempt to IAPManager
func restore_transactions() -> void:
	IAPManager.restore_transactions()


# purchase callback, result is Dictionary or null
func _purchase_result(success: bool, result):
	_processingPurchasesCount -= 1
	_processingPurchasesCount = clampi(_processingPurchasesCount, 0, 999)
	
	match success:
		true:
			_print_message(Color.GREEN, "Purchase validation success!")
			_print_message(Color.WHITE, "Raw: " + JSON.stringify(result))
	
			info_text.text = "Product purchase: " + result["data"]["productId"]
			info_text.text += "\n" + "Purchase result: " + str(success)
			info_text.text += "\n\n" + "See Log for more information!";
		false:
			_print_message(Color.RED, "Purchase validation failed.")
			info_text.text = "Purchase canceled."
	
	info_window.show()
	_print_message(Color.WHITE, "Purchase Processing Count: " + str(_processingPurchasesCount))
	_update_ui()


# message display
func _print_message(color: Color, text: String) -> void:
	log_text.text += "\n\n" + "[color=#" + color.to_html() + "]" + text + "[/color]";


# update graphical display of text contents with current states
# we rely on data from the billing system for this, but you could also persist the states locally
# because if billing cannot be initialized this returns false, so not practical for playing offline
func _update_ui() -> void:
	non_consumable_flag.visible = ReceiptValidator._is_purchased(IAPManager.product_definitions[1].id)
	subscription_flag.visible = ReceiptValidator._is_purchased(IAPManager.product_definitions[2].id)
