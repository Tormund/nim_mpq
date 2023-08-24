include dxt_emits
type
  DXT3PixelFormat* {.pure.} = enum
    BGRA = 0.cint
    RGBA = 1.cint
    ARGB = 2.cint
    ABGR = 3.cint

proc DXT3ReleaseLUTs*() {.importc.}
proc DXT3SetOutputPixelFormat*(pixelFormat: cint) {.importc.}
proc DXT3Decompress*(width: cuint, height: cuint, p_input: pointer, p_output: pointer) {.importc.}

proc DXT1ReleaseLUTs*() {.importc.}
proc DXT1SetOutputPixelFormat*(pixelFormat: cint) {.importc.}
proc DXT1Decompress*(width: cuint, height: cuint, p_input: pointer, p_output: pointer) {.importc.}

proc DXT5ReleaseLUTs*() {.importc.}
proc DXT5SetOutputPixelFormat*(pixelFormat: cint) {.importc.}
proc DXT5Decompress*(width: cuint, height: cuint, p_input: pointer, p_output: pointer) {.importc.}
