# Merge Battles

A Godot 4 game project using GDScript.

## Requirements

- [Godot 4.7](https://godotengine.org/download) (standard build, not .NET)

## Getting started

1. Open Godot, click **Import**, and select this folder's `project.godot`.
2. Press **F5** to run. The main scene is `scenes/main.tscn`.

From the command line:

```sh
godot --path . --editor   # open the editor
godot --path .            # run the game
```

## Project layout

```
project.godot     Project settings (720x1280 portrait, GL Compatibility renderer)
scenes/           Scenes (.tscn)
  main.tscn       Main scene (entry point)
  player.tscn     Example player (CharacterBody2D)
scripts/          GDScript files (.gd)
assets/           sprites/, audio/, fonts/
```

## Input actions

| Action       | Keys        |
|--------------|-------------|
| `move_left`  | A / Left    |
| `move_right` | D / Right   |
| `move_up`    | W / Up      |
| `move_down`  | S / Down    |

Esc (`ui_cancel`) quits the game.

## Notes

- `.godot/` is the editor cache. It is ignored by git and regenerated on import.
- Commit the `*.uid` and `*.import` files Godot creates next to your scripts and assets.
