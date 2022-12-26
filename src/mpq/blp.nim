# This is just an example to get you started. Users of your library will
# import this file by writing ``import mpq/submodule``. Feel free to rename or
# remove this file altogether. You may create additional modules alongside
# this file as required.

import unicode

type
  BLPType* {.pure.} = enum
    jpeg = 0
    directx = 1

  BLPEncoding* {.pure.} = enum
    uncompressed = 1
    directx = 2

  BLPAlphaEncoding* {.pure.} = enum
    dxt1 = 0
    dxt23 = 1
    dxt45 = 7

  BLPColor* {.packed.} = object
    r, g, b, a: uint8

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
    dataAUX: array[1024, byte]

  BLPDXHeaderAppendix {.packed.} = object
    palette: array[256, BLPColor]

  BLPJPEGHeaderAppendix {.packed.} = object
    headerSize: uint32
    data: array[1020, byte]

  BLPTexture* = ref object
    header*: BLPHeader
    mipmapsData*: seq[byte]

proc newBLPTextureFromData*(data: seq[byte]): BLPTexture =
  var r = new(BLPTexture)
  copyMem(addr r.header, unsafeAddr data[0], sizeof(BLPHeader))
  r.mipmapsData.setLen(data.len - sizeof(BLPHeader))
  copyMem(addr r.mipmapsData[0], unsafeAddr data[sizeof(BLPHeader)], data.len - sizeof(BLPHeader))
  # r.header = cast[BLPHeader](addr data[0])
  if r.header.magic != 844123202:
    raise newException(Exception, "Invalid texture")
  echo "BLP header : ", r.header
  echo "fileSize ", data.len, " mipmapsData: ", r.mipmapsData.len
  # if r.typ == BLPType.jpeg:


  # var blockSize = 16
  # if r.header.alphaEncodnig == BLPAlphaEncoding.dxt1.uint8:
  #   blockSize = 8


  result = r
