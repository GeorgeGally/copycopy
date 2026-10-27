# Critique

Judged from the PNGs in `shots/` only, as a still on a timeline and as a README image. The question for each: would this stop a scroll, and can you tell what the product is when it is small?

The glass is the same object in every frame: 720×238, radius 24, the two shadows from `Bezel.swift`, type above the tint. Neighbours are held at opacity 0.44 rather than the source's 0.34. At 0.34 a photograph and a white file icon fell under the threshold of a reduced still and the strip read as empty glass. 0.44 keeps them clearly behind the selected item. Selected stays at full size and full white.

Three rounds. Nothing under 8 shipped.

## Round 1

| | Score | Why it failed |
|---|---|---|
| Still | 6 | Dark panel, correct type, but the photograph was a smudge and the file icon had no red left in it. Same emptiness as the old preview, just darker. |
| Line | 5 | Scaled so far that the sentence sat in the top of a field of empty glass. The counter was a speck. It did not read as a panel. |
| Face | 8 | The portrait landed in the selected card and held the frame. Kept. |
| Page | 7 | The structure was right and the type did not collide, but the panel was a smaller copy of Still and the diary line was too modest to carry the thumbnail. |
| Name | 6 | The icon was true and "Roger" was set, and both were small in a large black field. |

## Round 2

Portrait re-cropped above the burned-in caption on `copy-that.png`, so the card is the face and not the words "I copy, over and out". Neighbours lifted to 0.44. Line recentred as a letterboxed card. Page's diary line set larger.

| | Score | Note |
|---|---|---|
| Still | 8 | Photograph, note, file, and "2 of 5" all present on paper. Held. |
| Line | 7 | Letterbox was cleaner, and still the same arrangement as Still, not large enough to read on a phone. Rebuilt. |
| Face | 9 | 73% of the selected card is skin. The face is centred. Held. |
| Page | 8 | "Thursday", "Sam at eleven.", the panel, and "Then the design review." sit in separate bands. Nothing clipped. Held. |
| Name | 7 | Icon correct, name correct, icon still small, dim neighbours as loud as the file. Rebuilt. |

## Round 3

Line scaled to 2× with six lines, so the note fills the card and the counter stays in frame. Name scaled to 1.28 and the caption moved above the panel so the file can be large. Still, Face, and Page untouched.

## Final

### 01 Still — 8

The whole panel, life size, on warm paper. A note selected between a photograph and a PDF.

This is the README image. You get the object at its real proportion: one item bright, the others back, "2 of 5" under them, a shadow that belongs to the metrics. It will not stop a scroll. At thumbnail size you get a dark rounded slab, a warm picture on the left, and a white document on the right, which is enough to tell it is not a grey box. The lower half of the text card is still air, because that is how centred 15pt type sits in a 184pt item.

### 02 Line — 8

The same panel pulled in until the sentence is the picture.

Six lines of the note, large enough that "Coffee with Sam at 11" still reads when the 1600px frame is shown around 500px wide. "2 of 5" survives at the bottom. The sides dissolve to black, so the crop does not slice a face in half. It is a poster of the clipboard, not a second colour of Still. A wall of mono is a specific taste; it is not pretty, and it is legible, which the old preview was not.

### 03 Face — 9

The copied image, selected and framed, on gallery white.

This is the one that stops a scroll. The selected card is the portrait, cover-cropped so the head fills it, radius 10, full brightness. The note and the PDF stay beside it, dimmer and smaller, so it is still the strip and not a lone photo. White ground, dark glass, a face. At thumbnail size the face is the whole story and the panel is the frame. Nothing else in the set does that.

### 04 Page — 8

The panel opened over a note. The diary line stays outside the glass.

"Sam at eleven." is set large, left, in a serif, with "Thursday" above it and "Then the design review." below. The panel sits between them and does not cover either line. It says the same appointment twice, once as a page and once as the thing you copied, which is the point and also the risk: a hurried reader thinks the headline is the product. No button, no gradient, no glow. Useful if the README needs words and a picture together. Face is the stronger post.

### 05 Name — 8

The file at full strength, and the only frame that says Roger.

The PDF is the selected item, big enough that the white page and the red badge survive a small card. "Roger" and ⌃⌥⌘V sit above it, because the panel never prints its own name and a GitHub unfurl has to. The neighbours are still there (the note, the rebase command), so it does not become an icon on a slide. More of a title card than Still, less of a picture than Face.

## For George

- README hero: **Face**, with Still as the alternate if the portrait feels too much like the existing Roger Moore art.
- The X post: **Face**.
- GitHub social preview: **Name**, because it is the only frame with the product's name. Face if the repo name beside the card is enough.

George picked **Still**.

## Selection

The selected item was only larger and brighter. At thumbnail size that is just "the bright card", and Return pastes whatever is bright. It needs a mark. Three treatments on Still only, judged from the PNGs, including each hero reduced to 480px wide. No glow, no shadow, no thick box.

The ring is a real rectangle, not a side rule. On the 1600px hero it spans 488×384 device pixels around the 472×368 item: a 1px stroke (two solid pixels of `#E6D3B0`) and 3px of glass on every side, top and bottom included. At @1x that stroke is one solid pixel of the same plate, not a half-covered fringe.

### (a) Warm plate — 9

`shots/v1-select-a-hero.png`, `shots/v1-select-a-social.png`

1px stroke, on whole pixels, 3px off the item, in the warm plate the bowtie is shown on (`#E6D3B0`). Thinned from 1.5px after this score. At 480px wide the side is still warm (about L112 against glass at L36) and the top holds at about L136. It does not touch the type, and it is not the same white as the words. This is the one.

### (b) White — 8

`shots/v1-select-b-hero.png`, `shots/v1-select-b-social.png`

The same offset in white, at the 1.5px weight it was scored. Higher raw contrast (side about L161, top about L215) and it is unmistakable. It is also the same white as the mono, so at thumbnail size the top rule sits against the glyphs and the mark starts to read as part of the type. Nothing of the brand in it that the type did not already spend.

### (c) Filled tile — 6

`shots/v1-select-c-hero.png`, `shots/v1-select-c-social.png`

A tile at `rgba(255,255,255,0.07)` behind the item, plus a 1px white rule on the item edge, no gap. The fill measures (51,51,53) against glass at (36,36,38), a lift of about 15. At 480px that tile is a faint lighter rectangle and the hairline (side about L140, top about L126) boxes the note instead of standing off it. The selection cue does not survive the thumbnail.

Shipped (a). `v1-still-hero.png` and `v1-still-social.png` were reshot from it and match `v1-select-a-hero.png` and `v1-select-a-social.png`.
