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
			_ClearCombineFlags()

	elif itemDragged && hoverSlot && hoverSlot.get_child_count() != 0:
		if CombineCheck(hoverSlot.get_child(0), itemDragged) == 6:
			canChamberRound = true
			_ClearCombineFlags()


# --- Release ----------------------------------------------------------------
# If a chamber action is pending, perform it and return early so the base
# Release() never runs.
#
# Magazine-attach correction: the base Item.Combine() auto-chambers a round
# when attaching a loaded magazine to an empty-chamber weapon (sets
# chamber=true, amount=mag-1). This happens before UpdateRig fires, so
# Magazine(true,true) sees chamber=true and plays MagazineAttachTactical.
# We intercept the attach ourselves, undo chamber=true right after Combine(),
# then call UpdateRig(true) which plays MagazineAttachEmpty. The data update
# (chamber=true, amount-=1 or just chamber=true) is handled inside
# WeaponRig.Magazine() — which branch fires depends on whether the weapon
# uses a slide-lock. See _AttachMagazineEmpty for details.
#
# For any other drag, delegate entirely to the base.

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

	if (itemDragged != null && hoverSlot != null
			&& hoverSlot.get_child_count() > 0
			&& itemDragged.slotData.itemData.subtype == "Magazine"
			&& itemDragged.slotData.amount > 0):
		var weaponItem = hoverSlot.get_child(0)
		var weaponData: WeaponData = weaponItem.slotData.itemData as WeaponData
		if (weaponData != null
				&& !weaponItem.slotData.chamber
				&& !_hasMagazine(weaponItem.slotData)
				&& ((hoverSlot.name == "Primary" && gameData.primary)
						|| (hoverSlot.name == "Secondary" && gameData.secondary))):
			_AttachMagazineEmpty(weaponItem)
			return

	super.Release()


# --- _AttachMagazineEmpty ---------------------------------------------------
# Attach a loaded magazine to an active weapon whose chamber is empty, playing
# the correct MagazineAttachEmpty animation instead of MagazineAttachTactical.
# Mirrors the base Release() combine path exactly, except that it undoes
# Combine()'s auto-chamber before UpdateRig(true) is called.

func _AttachMagazineEmpty(weaponItem) -> void:
	var magazineAmmo: int = itemDragged.slotData.amount
	var combineItem = itemDragged
	var weaponData: WeaponData = weaponItem.slotData.itemData as WeaponData

	weaponItem.Combine(combineItem)
	# Combine() set chamber=true and amount=mag-1 (auto-chamber). Undo chamber so
	# Magazine(true,true) takes the MagazineAttachEmpty path instead of Tactical.
	#
	# WeaponRig.Magazine() has two MagazineAttachEmpty branches:
	#  • Slide-lock branch (slideLock && slideLocked): sets chamber=true, does NOT
	#    decrement amount → keep Combine()'s already-decremented amount (mag-1).
	#  • Regular branch (!chamber && amount!=0): sets chamber=true AND decrements
	#    amount -= 1 → restore full amount so the final count is still mag-1.
	weaponItem.slotData.chamber = false
	if weaponData == null || !weaponData.slideLock:
		weaponItem.slotData.amount = magazineAmmo
	combineItem.queue_free()

	rigManager.UpdateRig(true)
	ChangeMagazine(hoverSlot)
	PlayAttach()
	Reset()


# --- ChamberRound -----------------------------------------------------------
# Consume one round from the dragged ammo stack and mark the weapon as having
# a round in the chamber. If the stack reaches zero it is removed from the
# grid; otherwise it is returned to its original slot.
#
# Guard against inventory-close during progress: if the player presses Tab
# while the progress bar is running, Close() calls Drop(itemDragged) which
# frees the UI item and then Reset() clears returnGrid/returnPosition. We
# capture both before the await so they survive Reset(), and we check
# is_instance_valid(combineItem) after the await — if it was freed we abort
# cleanly without chambering (the ammo is already on the ground).

func ChamberRound(targetItem):
	var combineItem = itemDragged
	# Save return context now — Close() → Reset() will null these during the await.
	var savedReturnGrid = returnGrid
	var savedReturnPosition = returnPosition

	gameData.isOccupied = true

	# Show the red-tinted progress circle over the weapon item (matches the
	# same visual used when clearing the chamber via UnloadWeapon).
	_StartProgress(targetItem)
	await activeProgress.completed
	if gameData.isDead: return

	if activeProgress:
		# If the inventory was closed mid-progress, Close() has already called
		# Drop(itemDragged) which freed the UI item. Abort without chambering
		# so we don't touch a freed object or corrupt weapon state.
		if not is_instance_valid(combineItem):
			activeProgress.queue_free()
			activeProgress = null
			gameData.isOccupied = false
			Reset()
			return

		# Mark the weapon chamber as loaded.
		targetItem.slotData.chamber = true
		targetItem.UpdateDetails()
		targetItem.UpdateSprite()

		# Consume one round.
		combineItem.slotData.amount -= 1

		if combineItem.slotData.amount <= 0:
			# Stack is empty — remove it entirely.
			# Use savedReturnGrid: Reset() may have cleared returnGrid already.
			if savedReturnGrid:
				savedReturnGrid.Pick(combineItem)
			combineItem.queue_free()
		else:
			# Return the reduced stack to its original grid position.
			# Restore saved context so Return() can place the item correctly.
			returnGrid = savedReturnGrid
			returnPosition = savedReturnPosition
			Return(combineItem)
			combineItem.UpdateDetails()

		# When the weapon is actively held in a rig slot, trigger the rig update
		# so the slide/hammer animations reflect the new chambered state.
		# Use animate=false so UpdateRig does not trigger magazine-attach animations
		# when a magazine is attached — the charge animation handles the visual.
		var rigIsActive = false
		if hoverSlot:
			var slotName = hoverSlot.name
			rigManager.UpdateRig(false)
			rigIsActive = ((slotName == "Primary" && gameData.primary)
					|| (slotName == "Secondary" && gameData.secondary))

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
# When a magazine is attached and the chamber is loaded, route to
# ClearChamberWithMag instead of the base UnloadWeapon (which would also
# empty the magazine ammo). When the chamber is empty with a magazine attached
# there is nothing to clear, so dismiss the menu.

func ContextUnload():
	if contextItem.slotData.itemData.type == "Weapon":
		var weaponData: WeaponData = contextItem.slotData.itemData as WeaponData
		if weaponData != null:
			if contextSlot && weaponData.weaponAction == "Manual":
				HideContext()
				return
			if weaponData.weaponAction != "Manual" && _hasMagazine(contextItem.slotData):
				if contextItem.slotData.chamber:
					var targetGrid = contextGrid if contextGrid != null else inventoryGrid
					ClearChamberWithMag(contextItem, targetGrid)
					HideContext()
					PlayClick()
					return
				else:
					HideContext()
					return
	super.ContextUnload()


# --- ClearChamberWithMag ----------------------------------------------------
# Ejects only the chambered round from a magazine-fed weapon without touching
# the magazine ammo (slotData.amount stays intact). Shows the same progress
# timer as the base unload, then uses UpdateRig(false) to refresh attachments
# without triggering magazine-attach/detach animations, and SlideLock(true)
# to visually reflect the now-empty chamber when the weapon is active.

func ClearChamberWithMag(targetItem, targetGrid):
	var equippedSlotName = ""
	if contextSlot:
		equippedSlotName = contextSlot.name

	var clearedSlotData = targetItem.slotData

	gameData.isOccupied = true

	var ammoData = targetItem.slotData.itemData.ammo

	_StartProgress(targetItem)
	await activeProgress.completed
	if gameData.isDead: return

	if activeProgress:
		# Clear only the chamber; leave magazine ammo (slotData.amount) intact.
		targetItem.slotData.chamber = false
		targetItem.UpdateDetails()
		targetItem.UpdateSprite()

		var newSlotData = SlotData.new()
		newSlotData.itemData = ammoData
		newSlotData.amount = 1

		if not AutoStack(newSlotData, targetGrid):
			Create(newSlotData, targetGrid, true)
			PlayStack()

		activeProgress.queue_free()
		activeProgress = null
		gameData.isOccupied = false
		Reset()

	if equippedSlotName != "":
		_RefreshRig(equippedSlotName, clearedSlotData, false, true)


# --- _hasMagazine -----------------------------------------------------------
# Returns true when the weapon SlotData has a nested magazine attached.

func _hasMagazine(slotData) -> bool:
	for nestedItem in slotData.nested:
		if nestedItem.subtype == "Magazine":
			return true
	return false


# --- UnloadWeapon -----------------------------------------------------------
# After the base async unload finishes, refresh the weapon rig when the weapon
# was actively held in the Primary or Secondary slot.
# When the action is a "Clear Chamber" (chamber=true, amount=0), also
# slide-lock the rig immediately to reflect the now-empty weapon state.

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
		_RefreshRig(equippedSlotName, clearedSlotData, true, isClearChamber)


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


# --- _StartProgress ---------------------------------------------------------
# Instantiate and show the progress circle over targetItem, then assign it to
# activeProgress so callers can await activeProgress.completed.

func _StartProgress(targetItem) -> void:
	var newProgress = progress.instantiate()
	add_child(newProgress)
	newProgress.global_position = targetItem.global_position
	newProgress.size = targetItem.size
	newProgress.Unload(1)
	activeProgress = newProgress


# --- _ClearCombineFlags -----------------------------------------------------
# Zero all combine-type flags so base Release() cannot trigger a standard
# combine while a chamber-round action is pending.

func _ClearCombineFlags() -> void:
	canCombine = false
	canCombineSwap = false
	canCombineLoad = false
	canCombineStack = false
	canCombineCharge = false


# --- _RefreshRig ------------------------------------------------------------
# Update the rig after a chamber-state change. animate_when_active controls
# whether UpdateRig is called with true (plays animations) when the slot is
# active; inactive slots always receive false. When slide_lock is true, also
# calls SlideLock(true) on the active rig if it still holds slotData.

func _RefreshRig(slotName: String, slotData, animate_when_active: bool, slide_lock: bool) -> void:
	var isActive = ((slotName == "Primary" && gameData.primary)
			|| (slotName == "Secondary" && gameData.secondary))
	rigManager.UpdateRig(animate_when_active && isActive)
	if slide_lock && isActive && rigManager.get_child_count() > 0:
		var rig = rigManager.get_child(rigManager.get_child_count() - 1)
		if (rig is WeaponRig) && rig.slotData == slotData:
			rig.SlideLock(true)


# --- _PlayChargeAnimation ---------------------------------------------------
# Half a second after chambering, trigger the Charge animation that is already
# compiled into every weapon's AnimationLibrary (baked from the GLB alongside
# all other animations).
#
# The existing Colt_1911_Charge animation is 1.8 s with all 98 tracks (body,
# arms, fingers, IK targets). Its duration matches the charge sound exactly,
# so both are started simultaneously. The Charge→Idle transition is
# switch_mode = AtEnd, so the state machine returns to Idle automatically
# when the animation ends.

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

	# Find the Charge animation by scanning the library for any name ending in
	# "_Charge". This handles weapons where data.file uses underscores but the
	# animation name uses hyphens (e.g. AK_12 vs AK-12_Charge).
	var lib: AnimationLibrary = rig.animations.get_animation_library("")
	var anim_name: String = ""
	for name in lib.get_animation_list():
		if name.ends_with("_Charge"):
			anim_name = name
			break
	var anim_length: float = 1.8  # safe fallback (Colt_1911 charge duration)
	if anim_name != "":
		anim_length = lib.get_animation(anim_name).length

	# Start the charge sound and the animation simultaneously.
	# Mirror the base game pattern: hold the condition true for 0.1 s so the
	# AnimationTree is guaranteed to tick and start the transition before we
	# clear it (same timer used by every animation trigger in WeaponRig.gd).
	rig.PlayCharge()
	rig.animator["parameters/conditions/Charge"] = true
	await get_tree().create_timer(0.1, false).timeout
	rig.animator["parameters/conditions/Charge"] = false

	# Release the slide lock when the animation finishes.
	# 0.1 s of the total duration has already elapsed above.
	await get_tree().create_timer(anim_length - 0.1, false).timeout
	rig.SlideLock(false)
