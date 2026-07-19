# M1 Art V2 Source Record

The two source images were generated through the built-in MCP tool `mcp__multica_imagegen__image_gen` in `mode=generate`, `quality=standard`. The tool reported model `gpt-image-2`, requested PNG output, and returned actual dimensions smaller than requested; the actual dimensions and hashes are recorded in the JSON manifest.

## Environment Source

Tool request: `size=1792x1024`, elapsed `83.17 s`, actual `1672x941`, `3005449` bytes, SHA-256 `0f01094229eae5f157d208e4dd378fcbdffa537493e1db0b1654eba7e37b0b7f`.

Final prompt:

> Use case: Godot 2D desktop game world background, final visual asset source for a xenobiotic hive-to-battlefield vertical slice.
> Asset type: one opaque 16:9 environment painting to be split into depth plates; no UI.
> Primary request: a continuous semi-realistic xenobiotic bio-industrial field manual environment, living chitin hive production on the left, breached transit throat in the center, hostile cavern battlefield with ruined modular equipment on the right.
> Scene/backdrop: subterranean graphite-black research installation fused with layered chitin ribs, translucent fungal membranes, branching root conduits, wet mineral floor, bone-white clamps and worn laboratory machinery, believable depth from foreground to distant background.
> Style/medium: semi-realistic 2D scientific field-manual painting, crisp inspectable silhouettes, tactile chitin ridges, membrane fibers, root veins, oxidized modular equipment, restrained local bioluminescence; cinematic game-world environment, not a UI.
> Composition/framing: wide side-on three-quarter 16:9 camera, continuous ground plane and readable left-to-right travel lane; keep top 14 percent and bottom 14 percent quiet for HUD/rail safe zones; foreground roots and clamps frame the lower edge without hiding the lane.
> Lighting/mood: controlled graphite shadows, bone-white rim on equipment, biomass green bounce in hive, information cyan instruments, thermal amber cores, sparse threat vermilion toward battlefield; no fog and no heavy bloom.
> Color palette: graphite black and bone white neutrals, biomass green, information cyan, thermal amber, threat vermilion; no dominant purple or blue.
> Constraints: opaque image, environment only, no characters, creatures, units, projectiles, explosions, text, letters, numbers, logo, watermark, cards, panels, buttons or labels, no embedded typography, coherent perspective, no cropped main architecture.
> Avoid: hard-edge geometric vector blocks, black empty placeholder shapes, dashboard composition, card grid, generic sci-fi UI, decorative orbs, bokeh, cartoon stickers, stock art, gore, gradients used as decoration.

## Specimen Atlas Source

Tool request: `size=2048x2048`, elapsed `218.52 s`, actual `1254x1254`, `2418352` bytes, SHA-256 `74616efd58fb48ce5d004335b8d0fc7fa6a98a22d881ae1c9c66009bb59753c6`.

Final prompt:

> Use case: Godot 2D game art specimen atlas, source image for separate transparent room, unit and VFX PNG assets.
> Asset type: one square scientific field-manual plate containing isolated visual specimens on a perfectly flat chroma green background for later local cutout; no UI.
> Primary request: thirteen distinct xenobiotic bio-industrial specimens arranged in a clean 4 by 4 research grid with generous spacing: three modular chitin hive-room modules (buildable open socket, running metabolic chamber with amber core, blocked chamber with a diagonal fracture), four insect swarm units (worker, wedge biter, root-spore carrier, hostile shielded enemy), and six non-text VFX glyphs (resource growth, contact clash, hit burst, hurt fracture, death shards, retreat trail).
> Style/medium: semi-realistic 2D scientific illustration, tactile layered chitin, fungal membrane fibers, root veins, worn metal clips, engraved contour accents, subtle local bioluminescence; readable silhouettes at 24–96 px.
> Composition/framing: every specimen fully contained in its own implied cell, front-facing or three-quarter, no overlap, no cropping, consistent light from upper left; room modules larger than units, VFX compact and asymmetric.
> Lighting/mood: controlled studio specimen lighting with soft contact shadow only inside each specimen, biomass green, information cyan, thermal amber, threat vermilion, bone highlights.
> Constraints: background must be a single uniform saturated chroma green with no texture; no text, letters, numbers, logos, watermark, labels, frames, UI panels, cards or icons; each specimen must use shape, notch, texture or direction as semantic code, never color alone; no purple-blue dominance.
> Avoid: black background, hard-edge geometric vector blocks, flat emoji or sticker style, cartoon anatomy, duplicate specimens, merged silhouettes, decorative gradients, bokeh, gore.

## Local Derivation

- Environment source was resized to `1920x1080` three times with Lanczos scaling and separate tonal depth passes: back `brightness=-0.18,saturation=0.82,boxblur=1:1`; mid `brightness=-0.03,contrast=1.04`; foreground `brightness=0.06,contrast=1.10,saturation=1.08,unsharp=5:5:0.5`. Each output was forced to RGBA PNG with compression level 9 and verified opaque.
- Atlas crops were locally chroma-keyed with `chromakey=0x00ff00:0.22:0.08`, converted to RGBA, scaled into fixed `512x512` room or `256x256` unit/VFX canvases, and padded with transparent corners. No source text or labels were copied into runtime assets.
- Crop cells, in source pixels: rooms `(0,0,420,400)`, `(410,0,430,400)`, `(830,0,424,400)`; units `(0,390,310,320)`, `(310,390,330,320)`, `(620,390,300,320)`, `(900,390,354,320)`; VFX `(0,680,320,320)`, `(300,680,350,320)`, `(630,680,320,320)`, `(930,680,324,320)`, `(0,930,340,320)`, `(430,930,420,320)`.
- Preview annotations are derived evidence only. The corrected rail contract marks `HUD SAFE 0 TO 14 PCT`, `ACTION FIELD 14 TO 78 PCT`, and `RAIL RESERVED 78 TO 100 PCT`; it also marks the measured icon top at 78.5 percent and rail line at 80.1 percent. These labels are not embedded in runtime assets.
