extends Node

var modSettings = preload("res://mods/chamberroundmanually/ModSettings.tres")
var McmHelpers = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")

const FILE_PATH = "user://MCM/ChamberRoundManually"
const MOD_ID = "ChamberRoundManually"
const MOD_VERSION = "2.1.0"

func _ready() -> void:
	var config = ConfigFile.new()

	config.set_value("Meta", "mod_version", MOD_VERSION)

	config.set_value("Dropdown", "modifier_key", {
		"name" = "Modifier Key",
		"tooltip" = "Hold this key while pressing the action key to chamber or eject the active weapon's chambered round. Set to None to trigger on the action key alone.",
		"default" = 1,
		"options" = ["None", "Shift", "Alt", "Ctrl"],
		"value" = 1,
		"menu_pos" = 1
	})

	config.set_value("Keycode", "action_key", {
		"name" = "Action Key",
		"tooltip" = "Press this key (together with the modifier, if set) to chamber a round (empty chamber) or eject the chambered round (loaded chamber).",
		"default" = 82,
		"default_type" = "Key",
		"type" = "Key",
		"value" = 82,
		"menu_pos" = 2
	})

	if !FileAccess.file_exists(FILE_PATH + "/config.ini"):
		DirAccess.open("user://").make_dir_recursive(FILE_PATH)
		config.save(FILE_PATH + "/config.ini")
	else:
		if McmHelpers != null:
			McmHelpers.CheckConfigurationHasUpdated(MOD_ID, config, FILE_PATH + "/config.ini")
		config.load(FILE_PATH + "/config.ini")

	_on_config_updated(config)

	if McmHelpers != null:
		McmHelpers.RegisterConfiguration(
			MOD_ID,
			"Chamber Round Manually",
			FILE_PATH,
			"Configure the key combination that chambers or ejects a round on the active weapon.",
			{
				"config.ini" = _on_config_updated
			}
		)

func _on_config_updated(config: ConfigFile) -> void:
	modSettings.modifier_key = config.get_value("Dropdown", "modifier_key")["value"]
	modSettings.action_key = int(config.get_value("Keycode", "action_key")["value"])
