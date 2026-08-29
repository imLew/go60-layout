# Per-key, per-layer RGB underglow on the Go60

A port of darknao's `rgb-layer-25.08` branch onto current `moergo-sc/zmk` `main`,
with the Go60 boards wired up.

**This has not been compiled or flashed.** See "What is untested" at the bottom.

## Why it ported cleanly

darknao's branch is based on `395eb4ae`, which is only 7 commits behind
`moergo-sc/zmk` `main` — and those 7 commits are mostly the Go60 board addition
itself. Rebasing his 17 feature commits onto `main` produced exactly one
conflict, in `lambda/compiler.rb` (MoErgo's Layout Editor build service, not used
by GitHub Actions builds). Resolved by keeping `main`'s snippet support and
darknao's change of passing `keymap_data` to the RHS build, which the feature
requires.

## Applying it

```bash
# fork moergo-sc/zmk on GitHub, then:
git clone https://github.com/YOUR-USER/zmk
cd zmk
git checkout -b go60-rgb-layer origin/main
git apply /path/to/go60-rgb-layer.patch
git commit -am "Per-key per-layer RGB underglow for Go60"
git push origin go60-rgb-layer
```

Then in your `go60-zmk-config` fork, edit `.github/workflows/build.yml`:

```yaml
      - uses: actions/checkout@v4
        with:
          repository: YOUR-USER/zmk
          ref: go60-rgb-layer
          path: src
```

## Enabling it

In `config/go60.conf`:

```ini
CONFIG_EXPERIMENTAL_RGB_LAYER=y
```

The feature is additionally gated on the `zmk,underglow-layer` node existing in
the devicetree with at least one child, so the Kconfig alone does nothing.

## Using it

In `config/go60.keymap`, add colour maps as children of the board's
`underglow-layer` node. `layer-id` is the keymap layer index; each `bindings`
array is 60 entries in key-position order, same order as a keymap layer.

```dts
#include <dt-bindings/zmk/rgb_colors.h>

&{/underglow-layer} {
    lower {
        layer-id = <1>;
        fade-delay = <10>;   // seconds before fading out; -1 = never
        bindings = <
    &ug ___    &ug RED    &ug RED    &ug RED    &ug RED    &ug RED       &ug ___  &ug ___  &ug ___  &ug ___  &ug ___  &ug ___
    &ug ___    &ug BLUE   &ug BLUE   &ug BLUE   &ug BLUE   &ug BLUE      &ug ___  &ug ___  &ug ___  &ug ___  &ug ___  &ug ___
    &ug ___    &ug ___    &ug ___    &ug ___    &ug ___    &ug ___       &ug ___  &ug ___  &ug ___  &ug ___  &ug ___  &ug ___
    &ug ___    &ug ___    &ug ___    &ug ___    &ug ___    &ug ___       &ug ___  &ug ___  &ug ___  &ug ___  &ug ___  &ug ___
                          &ug ___    &ug ___    &ug ___                           &ug ___  &ug ___  &ug ___
                                          &ug ___  &ug ___  &ug ___    &ug ___  &ug ___  &ug ___
        >;
    };
};
```

Available behaviours (all take a colour from `rgb_colors.h`, or a raw `0xRRGGBB`):

| Behaviour | Cells | Meaning |
|---|---|---|
| `&ug COLOR` | 1 | static colour |
| `&ug_cl ON OFF` | 2 | Caps Lock on/off colour |
| `&ug_nl ON OFF` | 2 | Num Lock on/off colour |
| `&ug_sl ON OFF` | 2 | Scroll Lock on/off colour |
| `&ug_b2 / _b4 / _b6 / _b8 ABOVE BELOW` | 2 | battery above/below 20/40/60/80% |

`___` is black (LED off). Layers with no `underglow-layer` child fall back to the
normal effect.

Turn it on at runtime the same way as before: `RGB_TOG`, then cycle `RGB_EFF`
until the layer effect is selected.

## What the port adds beyond the Glove80 version

Nothing functional — it's darknao's code unchanged apart from the rebase. The
Go60-specific work is the `underglow-layer` node in `go60_lh.dts` and
`go60_rh.dts`, plus `CONFIG_ZMK_SPLIT_PERIPHERAL_HID_INDICATORS=y` in both
defconfigs (and `CONFIG_ZMK_HID_INDICATORS=y` on the RH, which the LH already
had).

The `pixel-lookup` arrays map LED index to key position. I derived the left half
from the LED map comment in `go60_lh.dts` cross-referenced against the key
coordinates in `go60-layouts.dtsi`:

```
LED map (left)              key positions (left)
26 22 17 12  7  3            0  1  2  3  4  5
27 23 18 13  8  4           12 13 14 15 16 17
28 24 19 14  9  5           24 25 26 27 28 29
29 25 20 15 10  6           36 37 38 39 40 41
      21 16 11   0 1 2            48 49 50   54 55 56
```

Both arrays check out as exact permutations of their half's 30 key positions.

## What is untested

I could not compile this — the Nix build needs `cache.nixos.org` and
`cachix.org`, which aren't reachable from here — and obviously could not flash
it. Concretely:

1. **Not compiled.** The rebase is clean and the DTS is well-formed, but nothing
   has been through a compiler.

2. **The right-half LED map is an assumption.** `go60_rh.dts` carries no LED map
   comment, so the RH `pixel-lookup` is a mirror of the LH one. WS2812 chain
   order is a PCB property; if MoErgo didn't mirror the routing, the right half
   will light the wrong keys. Test by lighting one key on the RH and seeing where
   it lands.

3. **Thumb LED order is a guess** even on the left. LEDs 0, 1, 2 are mapped to
   key positions 54, 55, 56 (inner to outer). If they're reversed, swap them.

4. **Wired split is not supported.** darknao's layer propagation lives in
   `app/src/split/bluetooth/` (`peripheral_layers.c`, a new GATT characteristic),
   and `rgb_underglow_layer.c` includes
   `<zmk/split/bluetooth/peripheral_layers.h>` unconditionally on the peripheral.
   With `CONFIG_ZMK_SPLIT_WIRED` and BLE split off, this will fail to build. The
   Go60 defaults to BLE split, so this only bites if you've enabled wired split.

5. **Trackpads are untouched.** The Go60's Cirque sensors and `ZMK_POINTING` are
   enabled by default and were not present on the Glove80 that darknao targeted.
   Nothing in the port interacts with them, but they do share the RHS build and
   compete for flash — worth watching for size failures.

6. **Layer-change latency on the right half** depends on the new split
   characteristic. darknao added an idle connection-interval feature
   (`ZMK_SPLIT_BLE_PREF_IDLE`) partly to manage the battery cost of this; expect
   the RH to lag the LH slightly when switching layers after idle.

The `underglow_indicators` status overlay (battery/BT/lock state) is unchanged
and still left-half only.
