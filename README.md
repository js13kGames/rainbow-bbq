# Rainbow BBQ

My entry for the JS13K 2026 gamejam.

> **Please note:** This repository only contains source code up to- and including the version of the game submitted to JS13K. The "directors cut" version, as well as any future development, takes place on [Codeberg](https://codeberg.org/sukus/js13k-2026). The GitHub repository will not receive any more code updates.

You play as a unicorn, dashing into enemies of different colors of the rainbow, and use your unicorn horn as a grill spear to cook them and gain a higher score.

My goals for this project were to have as few dependencies as possible, and re-invent the wheel whenever possible. The game itself can be compiled and played in debug mode with zero additional dependencies required, but additional optimization passes make use of [Binaryen](https://github.com/webassembly/binaryen), and zipping for release uses [Info-ZIP](https://infozip.sourceforge.net).

## Building

This project was built with a pre-release version of Zig, version `0.17.0-dev.1936+5a625d5f3`.
Zig 0.16 won't work, and the full release of 0.17 [probably won't work either](https://codeberg.org/ziglang/zig/pulls/30875).

To build a debug build, simply do:

```sh
zig build
```

To build a release build, you need to have the following installed and available on your PATH:

* `wasm-opt` from [Binaryen](https://github.com/webassembly/binaryen)
* `zip` from [Info-ZIP](https://infozip.sourceforge.net)

Then build the game using the following command:

```sh
zig build zip -Doptimize=small
```

## Home-grown tools

This project contains several home-grown tools. Both some to replace common ones, like a JS transpiler, and some custom tools to aid in compression and ease of development.

### Texture builder

A script that renders [Aseprite](https://www.aseprite.org) files to flat images, converts them to 1BPP, and places them onto a texture atlas. It then emits both that atlas file, AND a Zig file containing the UV-coordinates of individual sprites/frames.

Incorporating this into the build system was really nice, as I could edit a sprite, save it and immediately see the changes in-game. This is a tool I'm taking with me, not just for next year, but for other projects in general!

### World builder

The level is also built from an [Aseprite](https://www.aseprite.org) file, as that was the quickest way I could come up with to get a visual editor going, with less than 36 hours before the submission deadline. It *works*, but it's not great. For future jams, I really need to build an actual level editor.

### Custom HTML, JS and GLSL minifiers

Built for the sport of doing it myself. I had ideas for several optimizations I could make to the JS code, but the project didn't end up using enough JS for it to be worth the time.

The minifiers do support removing whitespace and some otherwise redundant characters. The JS minifier supports inlining GLSL source code automatically, and the HTML minifier in turn supports inlining JS.

I'm probably bringing these with me for next time, as it's really nice to have everything incorporated into the Zig build system, without relying on NPM.

### WASM minifier

In order to save a little bit of space, I decided to strip all namespace names from my declared WASM imports, and make the name an integer. This meant that in the WASM module, the name/namespace of a function only takes 3-4 bytes total, and on the JS side, I can declare my imports as an array, and avoid having to specify key names, saving more bytes.

Aside from that, Zig (or LLVM maybe) has some awkward codegen when optimizing for size. It is particularly an issue around `f32.const`, `f64.const`, `v128.const` and `i8x16.shuffle`. These instructions have relatively large operands, and can in many cases be replaced by multiple smaller instructions to achieve the same result. See the [WASM optimizations](./WASM%20optimizations.md) document for more information on these optimizations.
