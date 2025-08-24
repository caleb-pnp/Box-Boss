Host-only controller architecture

- Game remains the single authority that loads maps and orchestrates the active controller.
- A "controller" is any Node extending GameControllerBase. Game instantiates one on "start".
- Controllers receive:
  - on_enter(params): configure timers, thresholds, and optional selection data.
  - on_map_ready(map): when the map instance emits map_ready (if requires_map_ready=true).
  - tick(delta): per-frame logic.
  - on_punch(source_id, force): centralized input from PunchInputRouter.
  - on_exit(): cleanup when swapping controllers.

Launching controllers (host-only)
- main.execute_command("start", [controller_ref, map_path, params])
  - controller_ref can be:
	- "PreFight", "StrongestWins", "LiveWindows", "CommandStyle"
	- a .gd script path with a class_name
	- a .tscn path whose root extends GameControllerBase
  - map_path optional. If provided, MapManager.load_map(map_path) is called locally.
  - params optional Dictionary passed to on_enter().

Pre-fight selection
- PreFightController runs:
  1) Character Select (30s): first punch joins a source; further punches cycle their character.
  2) Attack Set Select (30s): joined sources cycle their attack set.
  3) Mode Select (15s): any punch cycles the mode; last choice wins.
- When done, PreFightController calls Game.begin_local_controller(chosen_mode, same map, params_with_roster).

Extending to multiplayer later
- Replace begin_local_controller with an RPC entrypoint that calls the same sequence on all peers.
