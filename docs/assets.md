# Game asset credits and sources

| Asset | Project source | Verification |
| --- | --- | --- |
| Workshop pixel sprites | [generate_art.py](../scripts/generate_art.py) | The generator draws sprites and atlases from primitives. Running it and the font generator in a clean directory reproduces 28 PNGs pixel for pixel. |
| Cyrillic and Latin bitmap font | [generate_font.py](../scripts/generate_font.py) | The script defines the glyph matrices and uses them to produce the atlas and the `workshop_font.fnt` descriptor. |
| Music and sound effects | [generate_audio.py](../scripts/generate_audio.py) | Procedural synthesis reproduces all 36 WAV files in this version byte for byte. |
| Game icon | [icon.svg](../art/icon.svg) | The repository includes the vector source. The [art brief](workshop-visual.md) identifies the icon as original work. |

## Eight additional project PNGs

The following files in `art/` were added in commit `bd56a63` separately from the generator. Ilya confirmed that all eight belong to the project.

- `crane_mechanic.png`, `crate_metal.png`
- `engineer_goggles.png`, `hero_workshop_gear.png`
- `hunting_boots.png`, `slingshot.png`
- `traps.png`, `watch_cap.png`

Before distribution, document each file’s creator and rights holder, the image’s source, any terms for the source material, and permission to distribute the PNG in source and build packages. Record any required attribution. When the supporting records are private, the public description only needs to state the established origin and terms of use.

The plan cites Stack Attack, Braid and Dead Cells as references for mechanics and art direction. An asset’s origin and permission to reuse it are separate questions. The rights holder decides how to license the code and game assets.

## Engine and third-party components

The official [LICENSE.txt](https://github.com/godotengine/godot/blob/4.7.2-stable/LICENSE.txt) and [COPYRIGHT.txt](https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt) come from the Godot version pinned by the project. Copies are in [notices](../notices/) and are included in the build. When updating the engine, compare both files with the corresponding tag. See [Godot’s license distribution guidance](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html).
