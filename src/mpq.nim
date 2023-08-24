import os, streams, strutils, zippy

#TODO: think about it - #pragma pack(push, 1)

const MPQMaxTableEntries* = 1024 * 1024 * 1024

type
  MPQFormatVersion* {.pure.} = enum
    v1 = 0
    v2 = 1
    v3 = 2
    v4 = 3

  MPQCompression* {.pure.} = enum
    huffman = 0x01
    zlib = 0x02
    pkware = 0x03
    bzip2 = 0x10
    lzma = 0x12
    sparse = 0x20
    adpcm_mono = 0x40
    adpcm_stereo = 0x80

  MPQFileFlags* {.pure.} = enum
    compressed   = 0x00000200
    patchFile    = 0x00100000
    singleUnit   = 0x01000000
    deleteMarker = 0x02000000
    sectorCRC    = 0x04000000
    exists       = 0x80000000

  MPQHashType* {.pure.} = enum
    start, hash1, hash2, tableKey, count

type
  MPQHeader* {.packed.} = object
    magic*: uint32
    headerSize*: uint32
    archiveSize*: uint32
    format*: uint16
    blockSize*: uint16
    hashTableOffset*: uint32
    blockTableOffset*: uint32
    hashTableEntries*: uint32
    blockTableEntries*: uint32

  MPQV2Header* {.packed.} = object
    highBlockTableOffset*: uint64
    hashTableOffsetHight*: uint16
    blockTableOffsetHight*: uint16

  MPQV3Header* {.packed.} = object
    archiveSize*: uint64
    betOffset*: uint64
    hetOffset*: uint64

  MPQV4Header* {.packed.} = object
    compressedHashTableSize*: uint64
    compressedBlockTableSize*: uint64
    compressedHighBlockTableSize*: uint64
    compressedHETTableSize*: uint64
    compressedBETTableSize*: uint64
    md5ChunkSize*: uint32
    blockTableMD5*: array[16, char]
    hashTableMD5*: array[16, char]
    highBlockTableMD5*: array[16, char]
    betTableMD5*: array[16, char]
    hetTableMD5*: array[16, char]
    headerMD5*: array[16, char]

  MPQHashTableEntry* {.packed.} = object
    hash1*: uint32
    hash2*: uint32
    locale*: uint16
    platform*: uint16
    blockIndex*: uint32

  MPQBlockTableEntry* {.packed.} = object
    offset*: uint32
    compressedSize*: uint32
    uncompressedSize*: uint32
    flags*: uint32

  MPQHighBlockTableEntry* {.packed.} = object
    offsetHigh*: uint16

type
  MPQFile* = ref object
    data*: seq[byte]
    size*: uint32
    flags*: uint32

  MPQObj* = ref object
    path: string
    file: FileStream
    isInitialized: bool
    header*: MPQHeader
    headerV2*: MPQV2Header
    headerV3*: MPQV3Header
    headerV4*: MPQV4Header
    hashTable*: seq[MPQHashTableEntry]
    blockTable*: seq[MPQBlockTableEntry]
    highBlockTable*: seq[MPQHighBlockTableEntry]

proc dumpFlags*(f: uint32) =
  template flagChech(flag: MPQFileFlags): string =
    var res1 = "No"
    if (f and flag.uint32) != 0'u32:
      res1 = "Yes"
    res1

  var res = "Flags:\n"
  res &= "  compressed - " & flagChech(MPQFileFlags.compressed) & "\n"
  res &= "  patchFile - " & flagChech(MPQFileFlags.patchFile) & "\n"
  res &= "  singleUnit - " & flagChech(MPQFileFlags.singleUnit) & "\n"
  res &= "  deleteMarker - " & flagChech(MPQFileFlags.deleteMarker) & "\n"
  res &= "  sectorCRC - " & flagChech(MPQFileFlags.sectorCRC) & "\n"
  res &= "  exists - " & flagChech(MPQFileFlags.exists) & "\n"
  echo res

proc newMPQDecryptTable*(): array[0x500, uint32] {.compileTime.} =
  var seed = 0x00100001
  for i in 0 ..< 0x100:
    var j = i
    for k in 0 ..< 5:
      seed = (seed * 125 + 3) mod 0x2AAAAB
      var a = (seed and 0xFFFF) shl 0x10
      seed = (seed * 125 + 3) mod 0x2AAAAB
      var b = seed and 0xFFFF
      result[j] = uint32(a or b)
      j += 0x100

const gMPQDecryptTable = newMPQDecryptTable()

proc mpqHashString*(str: string, typ: MPQHashType): uint32 =
  if typ >= MPQHashType.count:
    return 0
  var seed1 = 0x7FED7FED'u32
  var seed2 = 0xEEEEEEEE'u32
  for ch in str:
    var c: uint32 = uint32(ch.toUpperAscii)
    seed1 = gMPQDecryptTable[(int(typ) shl 8) + int(c)] xor uint32(seed1 + seed2)
    seed2 = c + seed1 + seed2 + (seed2 shl 5) + 3
  result = seed1

# type DecrTyp = byte | char | uint8 | int8
# proc mpqDecryptTable*[DecrTyp](data: var openArray[DecrTyp], key: string) =
proc mpqDecryptTable*[T](data: var openArray[T], key: string) =
  var seed1 = mpqHashString(key, MPQHashType.tableKey)
  var seed2 = 0xEEEEEEEE'u32
  var seqPtr: pointer = addr data[0];
  const chunk = sizeof(uint32)
  let dataSize = data.len * sizeof(T)
  var t: uint32
  var i = 0
  while i < dataSize:
    seed2 += gMPQDecryptTable[0x400 + int(seed1 and 0xFF)]
    copyMem(addr t, cast[pointer](cast[int](seqPtr) + i), chunk)
    var c = t xor (seed1 + seed2)
    seed1 = ((not seed1 shl 0x15) + 0x11111111) or (seed1 shr 0x0B)
    seed2 = c + seed2 + (seed2 shl 5'u32) + 3'u32
    copyMem(cast[pointer](cast[int](seqPtr) + i), addr c, chunk)
    i += 4

proc getBlockIndex*(o: MPQObj, name: string): uint32 =
  if not o.isInitialized:
    raise newException(Exception, "MPQ isn't initialized")
  var index = (int) mpqHashString(name, MPQHashType.start) and (o.header.hashTableEntries - 1)
  var hash1 = mpqHashString(name, MPQHashType.hash1)
  var hash2 = mpqHashString(name, MPQHashType.hash2)

  while index < o.hashTable.len:
    var entry = o.hashTable[index]
    # echo "index: ", index, " hashes (", hash1, ", ", hash2, ") != (", entry.hash1, ", ", entry.hash2, ")"
    if entry.hash1 == hash1 and entry.hash2 == hash2 and entry.blockIndex != 0xFFFFFFFF'u32:
      return entry.blockIndex
    inc index
  raise newException(Exception, "Can't find block:" & name)

proc getFileInfo*(o:MPQObj, index: int, size: var uint32, flags: var uint32) =
  size = o.blockTable[index].uncompressedSize
  flags = o.blockTable[index].flags

proc getFileInfo*(o:MPQObj, name: string, size: var uint32, flags: var uint32) =
  var blockIndex = o.getBlockIndex(name)
  o.getFileInfo(blockIndex.int, size, flags)

template compressionType(src: var seq[byte]): MPQCompression =
  src[0].MPQCompression

template dumpCompression(src: var seq[byte], path: string) =
  echo instantiationInfo(), " compression: ",  compressionType(src), " file: ", path

proc mpqDecompress[T](dest: var openArray[T], src: var seq[byte], path: string) =
  # dumpCompression(src, path)
  var res = uncompress(addr src[1], src.len - 1)
  # todo: test this
  copyMem(addr dest[0], addr res[0], res.len)

proc mpqDecompress(dest: var seq[byte], offset: int, src: var seq[byte], path: string): int =
  # dumpCompression(src, path)
  var res = uncompress(addr src[1], src.len - 1)
  copyMem(addr dest[offset], addr res[0], res.len)
  result = res.len

proc readFile*(o: MPQObj, name: string): MPQFile =
  var index = o.getBlockIndex(name).int
  result.new()
  o.getFileInfo(index, result.size, result.flags)
  if o.blockTable[index].uncompressedSize > result.size or o.blockTable[index].compressedSize > result.size:
    raise newException(Exception, "File invalid")

  var offset = o.blockTable[index].offset
  if o.highBlockTable.len > 0:
    offset = offset or (o.highBlockTable[index].offsetHigh.uint32 shl 32)

  var blockSize = 0x200 shl o.header.blockSize
  var blocks = uint32(int(o.blockTable[index].uncompressedSize.int + blockSize + 1) / blockSize)
  echo "blocks ", blocks, " block size ", blockSize
  if (result.flags and MPQFileFlags.compressed.uint32) == 0'u32:
    raise newException(Exception, "Uncompressed files is not supported")

  var bytes = 0
  if (result.flags and MPQFileFlags.singleUnit.uint32) != 0'u32:
    if o.blockTable[index].compressedSize > blockSize.uint32: #this check is nessesary?
      raise newException(Exception, "File size incorrect")
    o.file.setPosition(offset.int)
    var buffer = newSeq[byte](o.blockTable[index].compressedSize)
    if o.file.readData(addr buffer[0], buffer.len) != buffer.len:
      raise newException(Exception, "Can't read file")
    bytes += mpqDecompress(result.data, 0, buffer, name)
  else:
    result.data = newSeq[byte](result.size)
    var offset2 = offset.int
    var currentBlock: uint32
    var nextBlock: uint32

    o.file.setPosition(offset2)
    o.file.read(currentBlock)
    offset2 += 4
    for i in 0 ..< blocks:
      o.file.setPosition(offset2)
      o.file.read(nextBlock)
      offset2 += 4
      o.file.setPosition(offset.int + currentBlock.int)
      var size = (int)nextBlock - currentBlock
      if size > blockSize.int:
        raise newException(Exception, "Can't read block")
      var buffer = newSeq[byte](size)
      if o.file.readData(addr buffer[0], size) != size:
        raise newException(Exception, "Can't read block")
      # echo "read block ", currentBlock, " nb ", nextBlock, " size ", size
      bytes += mpqDecompress(result.data, bytes, buffer, name)

      currentBlock = nextBlock

  if bytes != result.size.int:
    raise newException(Exception, "File damaged. Bytes read: " & $bytes & " " & " size: " & $result.size)

proc init(o: MPQObj) =
  const sep: uint32 = 458313805
  const sep2: uint32 = 441536589
  o.isInitialized = false
  o.hashTable.setLen(0)
  o.blockTable.setLen(0)
  o.highBlockTable.setLen(0)
  # o.blockBuffer.setLen(0)

  # HEADERS
  var headerOffset: int = 0
  while true:
    if o.file.atEnd:
      raise newException(Exception, "Can't read header")

    var w: uint32
    o.file.read(w)
    if w == sep:
      o.file.setPosition(4)
      o.file.read(w)
      headerOffset += int(w)
      break
    elif w == sep2:
      break
    headerOffset += 0x200
    o.file.setPosition(0x200)

  o.file.setPosition(headerOffset)
  o.file.read(o.header)
  # echo "read header ", o.header, "\n", sizeof(o.header), " +v2 ", sizeof(o.headerV2) , " +v3 ", sizeof(o.headerV3), " +v4 ", sizeof(o.headerV4)

  if o.header.blockSize > 16:
    raise newException(Exception, "Can't read header")

  var hashTableOffset = o.header.hashTableOffset
  var blockTableOffset = o.header.blockTableOffset
  if o.header.format >= uint16(MPQFormatVersion.v2):
    o.file.read(o.headerV2)
    echo "read header v2 ", o.headerV2
    hashTableOffset += o.headerV2.hashTableOffsetHight shl 32
    blockTableOffset += o.headerV2.blockTableOffsetHight shl 32

    if o.header.format >= uint16(MPQFormatVersion.v3):
      o.file.read(o.headerV3)
      echo "read header v3 ", o.headerV3
      if o.header.format >= uint16(MPQFormatVersion.v4):
        o.file.read(o.headerV4)
        echo "read header v4 ", o.headerV4

  # HASH TABLE
  if o.header.hashTableEntries > MPQMaxTableEntries or (o.header.hashTableEntries and (o.header.hashTableEntries - 1)) > 0:
    raise newException(Exception, "Can't read hash table")
  o.hashTable.setLen(o.header.hashTableEntries)
  var hashTableSize = sizeof(MPQHashTableEntry).uint32 * o.header.hashTableEntries
  o.file.setPosition(hashTableOffset.int)
  if o.header.format >= uint16(MPQFormatVersion.v4) and o.headerV4.compressedHashTableSize != hashTableSize:
    if o.headerV4.compressedHashTableSize > hashTableSize:
      raise newException(Exception, "Can't read hash table")
    var buffer = newSeq[byte](o.headerV4.compressedHashTableSize)
    if o.file.readData(addr o.hashTable[0], int(o.headerV4.compressedHashTableSize)) != int(o.headerV4.compressedHashTableSize):
      raise newException(Exception, "Can't read hash table")
    mpqDecryptTable(buffer, "(hash table)")
    o.hashTable.mpqDecompress(buffer, o.path)
    echo "hashTable v4 ", o.hashTable

  else:
    if o.file.readData(addr o.hashTable[0], int(hashTableSize)) != int(hashTableSize):
      raise newException(Exception, "Can't read hash table")
    mpqDecryptTable(o.hashTable, "(hash table)")

  # BLOCKs
  if o.header.blockTableEntries > MPQMaxTableEntries:
    raise newException(Exception, "Can't read block table")
  o.file.setPosition(blockTableOffset.int)
  o.blockTable.setLen(o.header.blockTableEntries)
  var blockTableSize = sizeof(MPQBlockTableEntry).uint32 * o.header.blockTableEntries
  if o.header.format >= MPQFormatVersion.v4.uint16 and o.headerV4.compressedBlockTableSize != blockTableSize:
    if o.headerV4.compressedBlockTableSize > blockTableSize:
      raise newException(Exception, "Can't read block table")
    if o.file.readData(addr o.blockTable[0], int(o.headerV4.compressedBlockTableSize)) != int(o.headerV4.compressedBlockTableSize):
      raise newException(Exception, "Can't read block table")
    mpqDecryptTable(o.blockTable, "(block table)")
  else:
    if o.file.readData(addr o.blockTable[0], int(blockTableSize)) != int(blockTableSize):
      raise newException(Exception, "Can't read block table")
    mpqDecryptTable(o.blockTable, "(block table)")

  # Hight block table
  o.highBlockTable.setLen(o.header.blockTableEntries)
  if o.header.format > MPQFormatVersion.v2.uint16 and o.headerv2.highBlockTableOffset > 0:
    o.file.setPosition(o.headerv2.highBlockTableOffset.int)
    var highBlockTableSize = sizeof(MPQHighBlockTableEntry).uint32 * o.header.blockTableEntries
    if o.header.format > MPQFormatVersion.v4.uint16 and o.headerV4.compressedHighBlockTableSize != highBlockTableSize:
      if o.headerV4.compressedHighBlockTableSize > highBlockTableSize:
        raise newException(Exception, "Can't read high block table")
      var buffer = newSeq[byte](o.headerV4.compressedHighBlockTableSize)
      if o.file.readData(addr buffer[0], int(o.headerV4.compressedHighBlockTableSize)) != int(o.headerV4.compressedHighBlockTableSize):
        raise newException(Exception, "Can't read high block table")
      o.highBlockTable.mpqDecompress(buffer, o.path)
    else:
      if o.file.readData(addr o.highBlockTable[0], int(highBlockTableSize)) != int(highBlockTableSize):
        raise newException(Exception, "Can't read high block table")
      echo "high block table ", o.highBlockTable[0]
  o.isInitialized = true

proc newMPQ*(path: string): MPQObj =
  if not fileExists(path):
    raise newException(Exception, "No file " & path)

  result.new()
  result.path = path
  result.file = newFileStream(path)
  result.init()

proc free*(o: MPQObj) =
  if not o.file.isNil:
    o.file.close()