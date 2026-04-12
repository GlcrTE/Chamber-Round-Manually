extends "res://Scripts/Interface.gd"

# Tracks whether the current drag-over target accepts a "chamber round" action.
var canChamberRound = false


# --- CombineCheck -----------------------------------------------------------
# Return 6 when dragging ammo onto a weapon that is compatible and has an
# empty chamber. All other cases fall through to the base implementation.

func CombineCheck(targetItem, combineItem):
	if (targetItem.slotData.itemData.type == "Weapon"
			&& combineItem.slotData.itemData.type == "Ammo"):
		var weaponData: WeaponData = targetItem.slotData.itemData as WeaponData
		if (weaponData != null
				&& weaponData.ammo != null
				&& weaponData.ammo.file == combineItem.slotData.itemData.file
				&& !targetItem.slotData.chamber
				&& combineItem.slotData.amount > 0):
			return 6

	return super.CombineCheck(targetItem, combineItem)


# --- Hover ------------------------------------------------------------------
# After the base hover pass, detect compatibility == 6 and set canChamberRound.
# When the chamber action is active we clear every other combine flag so the
# base Release() cannot accidentally trigger a standard combine.

func Hover():
	super.Hover()

	canChamberRound = false

	if itemDragged && hoverItem:
		if CombineCheck(hoverItem, itemDragged) == 6:
			canChamberRound = true
			canCombine = false
			canCombineSwap = false
			canCombineLoad = false
			canCombineStack = false
			canCombineCharge = false

	elif itemDragged && hoverSlot && hoverSlot.get_child_count() != 0:
		if CombineCheck(hoverSlot.get_child(0), itemDragged) == 6:
			canChamberRound = true
			canCombine = false
			canCombineSwap = false
			canCombineLoad = false
			canCombineStack = false
			canCombineCharge = false


# --- Release ----------------------------------------------------------------
# If a chamber action is pending, perform it and return early so the base
# Release() never runs. For any other drag, delegate entirely to the base.

func Release():
	if canChamberRound:
		if hoverItem:
			ChamberRound(hoverItem)
		elif hoverSlot && hoverSlot.get_child_count() != 0:
			ChamberRound(hoverSlot.get_child(0))
		else:
			Return(itemDragged)
			Reset()
		PlayAmmoLoad()
		return

	super.Release()


# --- ChamberRound -----------------------------------------------------------
# Consume one round from the dragged ammo stack and mark the weapon as having
# a round in the chamber. If the stack reaches zero it is removed from the
# grid; otherwise it is returned to its original slot.

func ChamberRound(targetItem):
	var combineItem = itemDragged

	# Mark the weapon chamber as loaded.
	targetItem.slotData.chamber = true
	targetItem.UpdateDetails()
	targetItem.UpdateSprite()

	# Consume one round.
	combineItem.slotData.amount -= 1

	if combineItem.slotData.amount <= 0:
		# Stack is empty — remove it entirely.
		if returnGrid:
			returnGrid.Pick(combineItem)
		combineItem.queue_free()
	else:
		# Return the reduced stack to its original grid position.
		Return(combineItem)
		combineItem.UpdateDetails()

	# When the weapon is actively held in a rig slot, trigger the rig update
	# so the slide/hammer animations reflect the new chambered state.
	if hoverSlot:
		var slotName = hoverSlot.name
		if ((slotName == "Primary" && gameData.primary)
				|| (slotName == "Secondary" && gameData.secondary)):
			rigManager.UpdateRig(true)
		else:
			rigManager.UpdateRig(false)

	Reset()


# --- Highlight --------------------------------------------------------------
# After the base highlight pass, force a green highlight on the target when
# canChamberRound is active (the base pass would show a grid-placement
# preview or hide the highlight instead).

func Highlight():
	super.Highlight()

	if canChamberRound && itemDragged:
		if hoverItem:
			highlight.color = valid
			highlight.size = hoverItem.size
			highlight.global_position = hoverItem.global_position
			highlight.show()
		elif hoverSlot:
			highlight.color = valid
			highlight.size = hoverSlot.size
			highlight.global_position = hoverSlot.global_position
			highlight.show()


# --- Reset ------------------------------------------------------------------
# Clear canChamberRound alongside all the base state.

func Reset():
	canChamberRound = false
	super.Reset()


# --- PlayAmmoLoad -----------------------------------------------------------
# Play the same ammo-load sound the base game uses when clearing the chamber
# (audioLibrary.ammoLoad is inherited from the base Interface.gd preload).

func PlayAmmoLoad():
	var audio = audioInstance2D.instantiate()
	add_child(audio)
	audio.PlayInstance(audioLibrary.ammoLoad)
