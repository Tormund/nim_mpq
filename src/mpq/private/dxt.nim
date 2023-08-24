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

# type
#   DXT3PixelFormat* {.pure.} = enum
#     BGRA, RGBA, ARGB, ABGR

#   DXT3Shift = tuple
#     a, r, g, b: int

# proc shifts(format: DXT3PixelFormat): DXT3Shift =
#   if format == DXT3PixelFormat.BGRA:
#     return (24, 16, 8, 0)
#   if format == DXT3PixelFormat.RGBA:
#     return (24, 0, 8, 16)
#   if format == DXT3PixelFormat.ARGB:
#     return (0, 8, 16, 24)
#   return (0, 24, 16, 8) #ABGR

# proc prebuildAlpha(shifts: DXT3Shift): array[64, uint32] =
#   const lut = [
#     0,    17,  34,  51,  68,  85, 102, 119,
#     136, 153, 170, 187, 204, 221, 238, 255
#   ]

#   for i in 0 ..< 16:
#     result[i] = uint32(lut[i] shl shifts.a)

# proc prebuildRGB(shifts: DXT3Shift): tuple[r: array[4096, uint32], g: array[16384, uint32], b: array[4095, uint32]] =
#   const lut_4x8 = [
#     0,     8,  16,  25,  33,  41,  49,  58,
#     66,   74,  82,  90,  99, 107, 115, 123,
#     132, 140, 148, 156, 164, 173, 181, 189,
#     197, 205, 214, 222, 230, 238, 247, 255
#   ]

#   const lut_8x8 = [
#     0,     4,   8,  12,  16,  20,  24,  28,
#     32,   36,  40,  45,  49,  53,  57,  61,
#     65,   69,  73,  77,  81,  85,  89,  93,
#     97,  101, 105, 109, 113, 117, 121, 125,
#     130, 134, 138, 142, 146, 150, 154, 158,
#     162, 166, 170, 174, 178, 182, 186, 190,
#     194, 198, 202, 206, 210, 214, 219, 223,
#     227, 231, 235, 239, 243, 247, 251, 255
#   ]

#   for cc0 in 0 ..< 32:
#     for cc1 in 0 ..< 32:
#       let index = ((cc0 shl 5) or cc1) shl 2
#       result.r[index or 0] = uint32(lut_4x8[cc0] shl shifts.r)
#       result.b[index or 0] = uint32(lut_4x8[cc0] shl shifts.b)
#       result.r[index or 1] = uint32(lut_4x8[cc1] shl shifts.r)
#       result.b[index or 1] = uint32(lut_4x8[cc1] shl shifts.b)

#       result.r[index or 2] = uint32((((lut_4x8[cc0] * 2) + (lut_4x8[cc1])) div 3) shl shifts.r)
#       result.b[index or 2] = uint32((((lut_4x8[cc0] * 2) + (lut_4x8[cc1])) div 3) shl shifts.b)

#       result.r[index or 3] = uint32(((lut_4x8[cc0] + (lut_4x8[cc1] * 2)) div 3) shl shifts.r)
#       result.b[index or 3] = uint32(((lut_4x8[cc0] + (lut_4x8[cc1] * 2)) div 3) shl shifts.b)

#   for cc0 in 0 ..< 64:
#     for cc1 in 0 ..< 64:
#       let index = ((cc0 shl 6) or cc1) shl 2
#       result.g[index or 0] = uint32(lut_8x8[cc0] shl shifts.g)
#       result.g[index or 1] = uint32(lut_8x8[cc1] shl shifts.g)

#       result.g[index or 2] = uint32((((lut_8x8[cc0] * 2) + (lut_8x8[cc1])) div 3) shl shifts.g)
#       result.g[index or 3] = uint32((((lut_8x8[cc0]) + (lut_8x8[cc1] * 2)) div 3) shl shifts.g)

# # __DXT3_LUT_COLOR_VALUE_R[index | 2] = (uint)((uint)((byte)(((__DXT3_LUT_4x8[cc0] * 2) + (__DXT3_LUT_4x8[cc1])) / 3)) << __DXT3_LUT_COLOR_SHIFT_R);

# proc dxt3_decode*(format: DXT3PixelFormat, width, height: uint32, src: seq[byte], dst: var seq[byte]) =
#   let shifts = format.shifts()
#   let prebuildA = shifts.prebuildAlpha()
#   let (prebuildR, prebuildG, prebuildB) = shifts.prebuildRGB()

#   let target4scans = width shl 2
#   let xBlocks = (width + 3) shr 2
#   let yBlocks = (height + 3) shr 2

#   if (xBlocks shl 2 != width) or (yBlocks shl 2 != height):
#     assert(false, "Not implemented")

#   var target = 0
#   for yblock in 0 ..< yBlocks:

