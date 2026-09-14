# WASM optimizations

This helps optimize WASM modules in size, and circumvents some awkward codegen by Zig/LLVM.

## Integer float constant optimization

Floats are always encoded as 4 (or 8) byte values. Integers are encoded using LEB128, so lower values are encoded using fewer bytes. So if a floating point constant can represented by a low integer, we can emit that integer instead, and then convert it to a float using an additional instruction:

```wat
;; From 5 bytes...
f32.const 42

;; Down to 3 bytes...
i32.const 42
f32.convert_i32_s
```

## Constant vectors with identical* lanes

Since I was making a game in 3D, I elected to enable the WASM SIMD instructions. These provide faster and more efficient handling of vectors, both in terms of speed and code size. However, the Zig compiler still generates odd patterns that can easily be optimized.

Since `v128.const` always encodes the entire 128-bit vector (16 bytes) with no encoding, any gains here are potentially huge. First order of business: If all lanes of the vector are the same, emit one lane as a `f32.const` or `i32.const`, then use a corresponding `.splat` instruction to build a vector:

```wat
;; From 18 bytes...
v128.const f32x4 1 1 1 1

;; To 5-7 bytes...
f32.const 1     ;; Apply int-float optimization to save 2 more bytes
f32x4.splat
```

If only one of the lanes differ, we can still do a `.splat` to fill the majority of the lanes, and then simply replace the one lane that has a difference:

```wat
;; From 18 bytes...
v128.const f32x4 1 1 2 1

;; To 11-15 bytes...
f32.const 1     ;; Apply int-float optimization to save 2 more bytes
f32x4.splat
f32.const 2     ;; Apply int-float optimization to save 2 more bytes
f32x4.replace_lane 2
```

## Creating new vector from splat of another vectors lane

To do this, the Zig compiler (or the LLVM backend) likes to emit a `i8x16.shuffle` instruction. This is fine for most platforms, but on WASM it costs a whole 16-byte operand. So instead, we manually extract the lane, and perform a splat:

```wat
;; From 18 bytes...
i8x16.shuffle 4 5 6 7 4 5 6 7 4 5 6 7 4 5 6 7

;; To 5 bytes...
f32x4.extract_lane 1
f32x4.splat
```