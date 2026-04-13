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
				&& weaponData.weaponAction != "Manual"
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
			await ChamberRound(hoverItem)
		elif hoverSlot && hoverSlot.get_child_count() != 0:
			await ChamberRound(hoverSlot.get_child(0))
		else:
			Return(itemDragged)
			Reset()
		return

	super.Release()


# --- ChamberRound -----------------------------------------------------------
# Consume one round from the dragged ammo stack and mark the weapon as having
# a round in the chamber. If the stack reaches zero it is removed from the
# grid; otherwise it is returned to its original slot.

func ChamberRound(targetItem):
	var combineItem = itemDragged

	gameData.isOccupied = true

	# Show the red-tinted progress circle over the weapon item (matches the
	# same visual used when clearing the chamber via UnloadWeapon).
	var newProgress = progress.instantiate()
	add_child(newProgress)
	newProgress.global_position = targetItem.global_position
	newProgress.size = targetItem.size
	newProgress.Unload(1)
	activeProgress = newProgress

	await activeProgress.completed
	if gameData.isDead: return

	if activeProgress:
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
		var rigIsActive = false
		if hoverSlot:
			var slotName = hoverSlot.name
			if ((slotName == "Primary" && gameData.primary)
					|| (slotName == "Secondary" && gameData.secondary)):
				rigManager.UpdateRig(true)
				rigIsActive = true
			else:
				rigManager.UpdateRig(false)

		PlayAmmoLoad()
		_PlayChargeAnimation(targetItem.slotData, rigIsActive)

		activeProgress.queue_free()
		activeProgress = null
		gameData.isOccupied = false
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


# --- ShowContext ------------------------------------------------------------
# When the player right-clicks a weapon in an equipped slot (Primary/Secondary
# or any other equipment slot), the base ShowContext() sets contextSlot but
# leaves contextGrid null. Context.gd gates the "Unload"/"Clear Chamber"
# button on contextGrid being non-null, so the button never appears for
# equipped weapons. Pre-setting contextGrid = inventoryGrid before calling
# super fixes this: the super's hoverSlot branch never touches contextGrid,
# so our value persists through context.Update() and the button shows up.
#
# Side-effect: any context action that branches on contextGrid first (e.g.
# ContextRemove, ContextDrop) will now take the wrong path. Those functions
# are overridden below to restore contextGrid = null when contextSlot is set.

func ShowContext():
	if hoverSlot && hoverSlot.get_child_count() != 0:
		var slotItem = hoverSlot.get_child(0)
		var weaponData: WeaponData = slotItem.slotData.itemData as WeaponData
		if weaponData != null && weaponData.weaponAction != "Manual":
			contextGrid = inventoryGrid
	super.ShowContext()


# --- ContextRemove ----------------------------------------------------------
# ShowContext() sets contextGrid = inventoryGrid for equipped weapons, but
# ContextRemove() checks contextGrid first and skips the elif contextSlot
# branch that plays the rig animation, ChangeMagazine, and UpdateBulletsDetach.
# Null contextGrid when contextSlot is set so the base takes the correct path.

func ContextRemove(nestedIndex):
	if contextSlot:
		contextGrid = null
	super.ContextRemove(nestedIndex)


# --- ContextDrop ------------------------------------------------------------
# Same branch-order issue as ContextRemove: contextGrid branch calls
# contextGrid.Pick(contextItem), but the weapon lives in the slot, not in
# inventoryGrid. Null contextGrid so the base uses the contextSlot path.

func ContextDrop():
	if contextSlot:
		contextGrid = null
	super.ContextDrop()


# --- ContextUnload ----------------------------------------------------------
# Block the context-menu "Unload" action for manual-action weapons only when
# they are equipped (contextSlot is set). In inventory the base behaviour is
# unchanged.

func ContextUnload():
	if contextSlot && contextItem.slotData.itemData.type == "Weapon":
		var weaponData: WeaponData = contextItem.slotData.itemData as WeaponData
		if weaponData != null && weaponData.weaponAction == "Manual":
			HideContext()
			return
	super.ContextUnload()


# --- UnloadWeapon -----------------------------------------------------------
# After the base async unload finishes, refresh the weapon rig when the weapon
# was actively held in the Primary or Secondary slot.
# When the action is a "Clear Chamber" (chamber=true, amount=0), also slide-lock
# the rig and play the charge sound to reflect the now-empty weapon state.

func UnloadWeapon(targetItem, targetGrid):
	# Capture the slot name before the base Reset() clears contextSlot.
	var equippedSlotName = ""
	if contextSlot:
		equippedSlotName = contextSlot.name

	# Detect "Clear Chamber" before super zeroes slotData.chamber.
	var isClearChamber = targetItem.slotData.chamber && targetItem.slotData.amount == 0
	var clearedSlotData = targetItem.slotData

	await super.UnloadWeapon(targetItem, targetGrid)

	if equippedSlotName != "":
		var isActive = ((equippedSlotName == "Primary" && gameData.primary)
				|| (equippedSlotName == "Secondary" && gameData.secondary))
		if isActive:
			rigManager.UpdateRig(true)
		else:
			rigManager.UpdateRig(false)

		if isClearChamber && isActive:
			_PlayClearChamberEffect(clearedSlotData)


# --- _PlayClearChamberEffect ------------------------------------------------
# Called after the chamber is cleared on an actively held weapon. Slide-locks
# the rig (marking it visually empty) and plays the bolt-cycle charge sound.

func _PlayClearChamberEffect(weaponSlotData) -> void:
	if rigManager.get_child_count() == 0:
		return
	var rig = rigManager.get_child(rigManager.get_child_count() - 1)
	if not (rig is WeaponRig):
		return
	if rig.slotData != weaponSlotData:
		return

	rig.SlideLock(true)
	rig.PlayCharge()


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


# --- _PlayChargeAnimation ---------------------------------------------------
# Half a second after chambering, play the weapon-specific charge sound and
# the Charge animation on the active rig. Only runs when the weapon that was
# chambered is currently drawn (primary or secondary rig visible).
# After the animation finishes the rig returns to Idle automatically and the
# slide lock is released — leaving the weapon in a chamber-loaded ready state.

func _PlayChargeAnimation(weaponSlotData, rigWasActive: bool) -> void:
	if not rigWasActive:
		return

	await get_tree().create_timer(0.5, false).timeout

	# Bail out if the rig was holstered or swapped during the delay.
	if rigManager.get_child_count() == 0:
		return
	var rig = rigManager.get_child(rigManager.get_child_count() - 1)
	if not (rig is WeaponRig):
		return
	# Confirm the rig still holds the weapon we just chambered.
	if rig.slotData != weaponSlotData:
		return

	# Play the weapon-specific bolt/slide charge sound.
	rig.PlayCharge()

	# The Charge AnimationTree condition exists in every rig scene but is never
	# triggered by the base game's WeaponRig.gd — the animation is unused.
	# Uncomment if a future game update wires it up:
	#rig.animator["parameters/conditions/Charge"] = true
	#await get_tree().process_frame
	#rig.animator["parameters/conditions/Charge"] = false

	# Release the slide lock now that the chamber is loaded, matching the
	# state the rig would have had if the weapon were drawn already chambered.
	rig.SlideLock(false)
