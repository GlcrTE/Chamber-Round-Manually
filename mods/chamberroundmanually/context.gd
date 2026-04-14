extends "res://Scripts/Context.gd"

# --- Update -----------------------------------------------------------------
# Extend the base context menu to show "Clear Chamber" for non-manual weapons
# that have a loaded chamber even when the magazine still has ammo
# (slotData.amount > 0).  The base game gates the button on amount == 0, so
# the option was invisible whenever the magazine had rounds remaining.

func Update(slotData: SlotData):
	super.Update(slotData)

	if interface.contextGrid && interface.contextItem.slotData.itemData.type == "Weapon":
		if interface.contextItem.slotData.itemData.weaponAction != "Manual":
			if interface.contextItem.slotData.amount != 0 && interface.contextItem.slotData.chamber:
				var unloadButton = buttons.get_node("Unload")
				unloadButton.text = "Clear Chamber"
				unloadButton.show()
