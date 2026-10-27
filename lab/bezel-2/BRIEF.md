# Bezel lab 2

George's intent, verbatim:

> make 5 image of the bevel as a design lab, so we can choose the best for marketing. right now the preview is bad

## What is wrong with the current preview

`docs/screenshots/bezel.png` is the picture in the README today. It reads as a dim grey box.

- The glass is a washed, flat grey. `.hudWindow` plus the 40% black tint in `BezelRootView` should composite to a dark HUD. Shot over the flat light backdrop in `roger-shot`, the material went translucent and the type lost its ground.
- The copied image is cover-cropped (`scaledToFill` into 236×184) and then shoved into the left edge fade, so the subject is sliced.
- The selected line is 15pt mono, centred, with too little copy, so the middle of the panel is empty.
- The file icon sits on an unselected item (`opacity 0.34`, `scale 0.86`). On the washed grey it disappears.
- Nothing in the frame says what this is, and nothing in it is worth a second look.

The previous lab (`lab/shot-lab.html`, commit `786da11`) put that same capture on five backgrounds. These frames do not do that again.

## What the app actually draws

Faithful to `Sources/RogerCore/Bezel.swift`. Point sizes, drawn in CSS and shot at 2×.

| | |
|---|---|
| Panel | 720 × 238, corner radius 24 |
| Shadow | `0 18px 28px rgba(0,0,0,0.38)` and `0 2px 6px rgba(0,0,0,0.22)` (AppKit offsets point up; the shadow falls down) |
| Glass | HUD material with the sibling `black @ 0.40` tint. Text is drawn above the tint, not blended into it. Composited here as solid `#2C2C2E` so the shot does not depend on backdrop-filter. |
| Item | 236 × 184. Unselected: scale 0.86, opacity 0.34. No card chrome. |
| Strip | Selected item centred. Spacing 20. Edge fade 36. Neighbours are the newer item on the left and the older item on the right. |
| Text | 15pt regular mono, line spacing 4, centred, white 94%, padding 16×12, lifted 2pt. |
| Image | Cover-fill, clipped to radius 10. |
| File | 64pt workspace icon, name at 14pt medium, white 94%, centred, gap 14. |
| Counter | 12pt medium, tabular figures, white 50%. "`n` of `count`". Gap 10 above, row height 16. |

Sample items are real clipboard kinds only: a note, an image, a PDF, a shell command, a URL. Copy is tidied so a card does not sit empty. No features are added. The portrait is the existing `docs/screenshots/copy-that.png`, cover-cropped so the face sits inside the item instead of being sliced by it.

## The five directions

Not five colourways. The glass is the same object in every frame.

1. **Still.** The whole bezel, life size, on warm paper. Text selected, so the strip shows a picture, a note, and a file. The README object.
2. **Line.** A macro crop of the selected note: the sentence large enough to read on a phone, the counter kept, the glass edge at the bottom of the frame. The post.
3. **Face.** Image selected and framed. Gallery white. The picture is the thing that has to survive a timeline.
4. **Page.** The bezel set into a typeset note, the way it actually appears over work. Serif, left aligned, no headline treatment.
5. **Name.** File selected, so the PDF icon is at full strength and large enough to see. The word Roger and the shortcut sit above the bezel as a caption, because the panel itself never says the product's name.

## Brand

Roger, as in Roger Moore. The mark is the bowtie (`lab/assets/mark.png`). Minimal, editorial, non-corporate. No gradient glows, no SaaS lighting, no taglines.

## Done when

- [x] `lab/bezel-2/BRIEF.md` (this file) written before the frames
- [x] Five directions as HTML in `lab/bezel-2/`
- [x] Ten PNGs in `lab/bezel-2/shots/`: for each direction, a 1600×800 hero and a 1280×640 social, both shot at 2× from headless Chrome
- [x] `lab/bezel-2/CRITIQUE.md` with a score out of 10 for each hero, judged from the PNGs only. Anything under 8 rebuilt. At most 3 rounds.
- [x] `lab/bezel-2/index.html` contact sheet of all five
- [x] App source untouched. Branch and PR only. Not merged.
