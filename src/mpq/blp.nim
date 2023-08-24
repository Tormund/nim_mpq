import unicode, private/dxt

# https://wowpedia.fandom.com/wiki/BLP_files
type
  BLPType* {.pure.} = enum
    jpeg = 0
    directx = 1

  BLPEncoding* {.pure.} = enum
    raw1 = 1
    directx = 2
    raw3 = 3

  BLPAlphaEncoding* {.pure.} = enum
    dxt1 = 0'u8
    dxt23 = 1'u8
    dxt45 = 7'u8

  BLPColor* {.packed.} = object
    b, g, r, a: uint8

  BLPHeader* {.packed.} = object
    magic*: uint32
    typ*: uint32
    encoding*: uint8
    alphaDepth*: uint8
    alphaEncodnig*: uint8
    hasMips*: uint8
    width*: uint32
    height*: uint32
    offsets*: array[16, uint32]
    sizes*: array[16, uint32]
    palette: array[256, BLPColor]

  BLPJPEGHeaderAppendix {.packed.} = object
    headerSize: uint32
    data: array[1020, byte]

  BLPTexture* = ref object
    header*: BLPHeader
    mipmapsData*: seq[seq[byte]]

proc newBLPTextureFromData*(data: seq[byte]): BLPTexture =
  var r = new(BLPTexture)
  copyMem(addr r.header, unsafeAddr data[0], sizeof(BLPHeader))
  var mipMaps = 0
  for i in 0 ..< r.header.sizes.len:
    if r.header.sizes[i] == 0:
      break
    mipMaps.inc()

  var readSize = 0
  r.mipmapsData.setLen(mipMaps)
  for i in 0 ..< mipMaps:
    r.mipmapsData[i].setLen(r.header.sizes[i])
    readSize += r.header.sizes[i].int
    copyMem(addr r.mipmapsData[i][0], unsafeAddr data[r.header.offsets[i]], r.header.sizes[i])

  if r.header.magic != 844123202:
    raise newException(Exception, "Invalid texture")
  return r


proc getBitmap*(t: BLPTexture): seq[byte] =

  assert(t.mipmapsData.len > 0, "invalid size")
  # assert(result.len > 0, "invalid size")

  if t.header.typ != BLPType.directx.uint8:
    assert(false, "JPEG is not implemented: " & $t.header.typ)

  if t.header.encoding != BLPEncoding.directx.uint8 and t.header.encoding != BLPEncoding.raw1.uint8 and t.header.encoding != BLPEncoding.raw3.uint8:
    assert(false, "Invalid encoding " & $t.header.encoding)

  if t.header.encoding == BLPEncoding.raw3.uint8:
    assert(false, "Not implemented raw3 encoding")

  if t.header.encoding == BLPEncoding.raw1.uint8:
    result.setLen(t.header.width * t.header.height * 4)
    if t.header.alphaDepth == 0'u8:
      var i = 0
      var q = 0
      while q < t.mipmapsData[0].len:
        var color = t.header.palette[t.mipmapsData[0][q]]
        result[i] = color.r
        result[i + 1] = color.g
        result[i + 2] = color.b
        result[i + 3] = 255.byte
        i += 4
        inc q

    elif t.header.alphaDepth == 8'u8:
      # echo t.header
      var i = 0
      var q = 0
      let alphaFrom = int(t.header.width * t.header.height)
      while q < t.mipmapsData[0].len - alphaFrom:
        var color = t.header.palette[t.mipmapsData[0][q]]
        result[i] = color.r
        result[i + 1] = color.g
        result[i + 2] = color.b
        result[i + 3] = t.mipmapsData[0][alphaFrom + q] # 255.byte
        i += 4
        inc q

    elif t.header.alphaDepth == 1'u8:
      # echo t.header
      var i = 0
      var q = 0
      let alphaFrom = int(t.header.width * t.header.height)
      var currentAlphaBit = 0
      var alphaBytes = (alphaFrom div 8)
      while q < t.mipmapsData[0].len - alphaBytes:
        var color = t.header.palette[t.mipmapsData[0][q]]
        result[i] = color.r
        result[i + 1] = color.g
        result[i + 2] = color.b
        result[i + 3] = ((t.mipmapsData[0][alphaFrom + (q div 8)] shr currentAlphaBit) and 1) * 255
        i += 4
        inc q
        inc currentAlphaBit
        if currentAlphaBit > 6:
          currentAlphaBit = 0

    else:
      echo t.header
      assert(false, "Not implemented raw1 alphaDepth: " & $t.header.alphaDepth)
    return

  result.setLen(t.header.width * t.header.height * 4)
  if t.header.alphaEncodnig == BLPAlphaEncoding.dxt1.uint8:
    DXT1SetOutputPixelFormat(DXT3PixelFormat.RGBA.cint)
    DXT1Decompress(t.header.width.cuint, t.header.height.cuint, addr t.mipmapsData[0][0], addr result[0])
  elif t.header.alphaEncodnig == BLPAlphaEncoding.dxt23.uint8:
    DXT3SetOutputPixelFormat(DXT3PixelFormat.RGBA.cint)
    DXT3Decompress(t.header.width.cuint, t.header.height.cuint, addr t.mipmapsData[0][0], addr result[0])
  elif t.header.alphaEncodnig == BLPAlphaEncoding.dxt45.uint8:
    DXT5SetOutputPixelFormat(DXT3PixelFormat.RGBA.cint)
    DXT5Decompress(t.header.width.cuint, t.header.height.cuint, addr t.mipmapsData[0][0], addr result[0])
  else:
    assert(false, "Invalid alphaEncodnig " & $t.header.alphaEncodnig)

