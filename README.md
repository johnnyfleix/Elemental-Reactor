# Elemental Reactor — Godot 4 Project

A 2D physics sandbox demonstrating emergent elemental interactions.

## Import Instructions

1. Unzip this archive anywhere on your machine.
2. Open **Godot 4.2+** (use the same minor version or newer).
3. In the Project Manager, click **Import**.
4. Navigate to the unzipped folder and select `project.godot`.
5. Click **Import & Edit**. Godot will import assets automatically.
6. Press **F5** (or the Play button) to run.

## Controls

| Action | Input |
|--------|-------|
| Spawn element | Left-click (hold to spray) |
| Select Wood | Click "Wood" button |
| Select Fire | Click "Fire" button |
| Select Water | Click "Water" button |
| Select Metal | Click "Metal" button |

## Elemental Rules

| Element | Class | Behaviour |
|---------|-------|-----------|
| Wood | `Flammable` | Burns up after ~2s when near Fire or hot Metal |
| Fire | `HeatSource` | Ignites nearby Wood/Metal; destroyed by Water |
| Water | `Extinguisher` | Destroys Fire on contact; evaporates itself |
| Metal | `Conductor` | Heavy; heats up near Fire after 1.5s, then ignites adjacent Wood |

## Collision Layers

| Layer | Name | Used by |
|-------|------|---------|
| 1 | walls | StaticBody2D borders |
| 2 | bodies | Wood, Water, Metal, Fire physics bodies |
| 3 | fire_area | Fire's HeatArea (Area2D) |
| 4 | water_area | Water's WaterArea (Area2D) |
| 5 | conductor_area | Metal's ConductorArea (Area2D) |

## Replacing Placeholder Sprites

Each element uses a `ColorRect` as a placeholder. To swap in your Krita sprites:

1. Open the element scene (e.g. `scenes/elements/Wood.tscn`).
2. Delete the `ColorRect` node.
3. Add a `Sprite2D` node in its place.
4. Assign your spritesheet texture in the Inspector.
5. In `Flammable.gd`, change `@onready var _sprite : ColorRect` to `Sprite2D`
   and replace `.color =` with `.modulate =`.

## Project Structure

```
project.godot
icon.svg
scenes/
  Main.tscn
  elements/
    Wood.tscn
    Fire.tscn
    Water.tscn
    Metal.tscn
scripts/
  Main.gd
  Spawner.gd
  Flammable.gd
  HeatSource.gd
  Extinguisher.gd
  Conductor.gd
```
