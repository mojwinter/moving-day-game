@tool
extends EditorScript
## Dev-mode puzzle generator for loopy puzzles.
## Open this script in the editor and run with Script > Run (Ctrl+Shift+X).
##
## Each run generates ONE puzzle and appends it to the manifest.
## Edit NEXT_W, NEXT_H, NEXT_DIFF below to control what gets generated.
## The editor will freeze briefly during generation — this is normal.

const OUTPUT_DIR := "res://data/loopy_puzzles/"
const MANIFEST_PATH := "res://data/loopy_puzzles/manifest.json"
const DIFF_NAMES := ["easy", "normal", "tricky", "hard"]

## ---- EDIT THESE to control the next puzzle to generate ----
const NEXT_W := 7
const NEXT_H := 5
const NEXT_DIFF := 0  ## 0=easy, 1=normal, 2=tricky, 3=hard


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)

	# Load existing manifest to find next index
	var manifest_paths: Array = []
	var manifest_file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if manifest_file != null:
		var json := JSON.new()
		json.parse(manifest_file.get_as_text())
		manifest_file.close()
		if json.data is Dictionary and json.data.has("puzzles"):
			manifest_paths = json.data["puzzles"]

	var file_index: int = manifest_paths.size()
	var diff_name: String = DIFF_NAMES[NEXT_DIFF] if NEXT_DIFF < DIFF_NAMES.size() else "unknown"

	print("Generating puzzle %d (%dx%d %s)..." % [file_index + 1, NEXT_W, NEXT_H, diff_name])

	var native := LoopyNative.new()
	var data: Dictionary = native.generate_puzzle(NEXT_W, NEXT_H, NEXT_DIFF)

	# Add metadata
	data["meta"] = {
		"difficulty": diff_name,
		"difficulty_int": NEXT_DIFF,
		"grid_w": NEXT_W,
		"grid_h": NEXT_H,
		"index": file_index,
	}

	# Write JSON
	var filename := "puzzle_%03d.json" % file_index
	var path := OUTPUT_DIR + filename
	var json_string := JSON.stringify(data, "  ")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("ERROR: Could not write %s" % path)
		return
	file.store_string(json_string)
	file.close()

	# Update manifest
	manifest_paths.append(path)
	var manifest := {"puzzles": manifest_paths}
	var mf := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, "  "))
	mf.close()

	print("  -> Saved %s (%d total puzzles in manifest)" % [filename, manifest_paths.size()])
