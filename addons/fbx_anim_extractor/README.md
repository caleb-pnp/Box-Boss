# FBX Animation + Root Motion Tools

An editor plugin for Godot 4 that:
- Extracts a single animation clip from imported `.fbx` files into standalone `Animation` resources.
- Removes Mixamo-style root motion (zeroes Hips X/Z) from:
  - Animations inside `AnimationLibrary` resources.
  - Standalone `Animation` resources (`.tres`/`.res`).

## Install

1. Copy `addons/fbx_anim_extractor` into your project.
2. Enable the plugin in Project Settings → Plugins.

## Use

### Extract animation from FBX
- Project menu → "FBX: Extract Animation…"
- Select one or more `.fbx` files.
- For each file:
  - Loads the imported scene (`PackedScene`)
  - Finds the first `AnimationPlayer`
  - Duplicates the first animation (warns if multiple)
  - Saves as `res://<fbx_dir>/extracted/<fbx_basename>.tres`

### Remove Mixamo root motion
- Project menu → "Animations: Remove Mixamo Root Motion…"
- Select one or more files:
  - `AnimationLibrary` (`.tres` or `.res`)
  - Standalone `Animation` (`.tres` or `.res`)
- A dialog lists all found animations; choose which to process.
- Processing:
  - Finds the Hips position track (Animation.TYPE_POSITION_3D where track path contains "Hips")
  - Sets X and Z of all keyframes to 0.0 (keeps Y)
  - Saves modified resources:
	- AnimationLibrary files are saved once after processing all chosen clips.
	- Standalone Animation files are saved directly.

## Notes

- For rigs not using "Hips" as pelvis name, change the string in `_remove_root_motion_from_animation()`.
- If you still see “Attempting to make child window exclusive,” it means a modal was still open. The plugin hides/frees file dialogs and defers next steps to prevent this, so ensure you’re on Godot 4.0+ and the plugin is reloaded.
