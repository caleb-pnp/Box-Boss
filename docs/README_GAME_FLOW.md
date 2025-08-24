High-level flow

- After "Start", the game runs three pre-fight selection screens in order:
  1) Character Select (30s)
	 - Any bag punch joins a player slot and cycles their character index.
	 - UI shows a colored highlight ring (player color) on the currently selected character tile.
  2) Attack Set Select (30s)
	 - Same mechanic: punch cycles through your Attack Set (Quick, Heavy, Mixed, MMA).
  3) Mode Select (15s)
	 - Punch to cycle the active game mode (any player can change it).
	 - When time expires, the current mode is chosen.

- Fight scene starts according to the selected Game Mode:
  - Strongest Wins: turn-based force windows are recorded, then a cinematic replay is generated showing blocks/hits and a KO at the end.
  - Live Battle, Punch Windows: 60s continuous, with a “punch window” flashing every 5 seconds. Hits in the window execute; outside the window, they’re ignored or buffered (tunable).
  - Live Battle, Command Style: each hit maps to a command; the fighters follow queued commands with auto-dodge when both are about to swing.

Implementation Notes

- Punch inputs come from PunchInputRouter (autoload or scene child). Each physical bag you wire in should call router.simulate_punch(source_id, force) or emit router.punched(source_id, force).
- Player slots are assigned on first punch from a new source_id, up to max_players.
- Character roster and Attack Set lists are defined in GameFlow.boot(); replace with your real data (scene paths, icons, attack sets).
- All scripts are typed for Godot 4.x to avoid Variant inference errors.

How to wire quickly

1) Add autoloads:
   - Autoload "GameFlow" from res://autoload/game_flow.gd
   - Optional: Autoload "PunchInputRouter" from res://input/punch_input.gd (or add it as a child where you handle inputs)

2) Make three control scenes (or reuse an existing UI):
   - CharacterSelect.tscn with script ui/character_select.gd
   - AttackSetSelect.tscn with script ui/attackset_select.gd
   - ModeSelect.tscn with script ui/mode_select.gd
   Hook their on_ready and on_timeout to GameFlow to advance.

3) On real hardware punch:
   - Call PunchInputRouter.simulate_punch(source_id, force) whenever a bag registers a hit.
   - Or connect your hardware’s “punched(force)” signal to PunchInputRouter.forward_punch(source_id, force).

4) Start:
   - GameFlow.go_to_character_select()

5) Fight scene:
   - Make a scene with two BaseCharacter nodes and attach scenes/fight_scene.gd as the root script.
   - GameFlow.start_mode() will instance the chosen GameMode with PlayerSlot contexts and hand over control to FightScene.
