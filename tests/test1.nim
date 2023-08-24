# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest, os, strutils
import nimPNG
import mpq, mpq/blp
const testFile = """E:\Games\World of Warcraft\Data\common.MPQ"""
const testFile2 = """E:\Games\World of Warcraft\Data\patch-2.MPQ"""
const testFile3 = """E:\Games\World of Warcraft\Data\enGB\expansion-locale-enGB.MPQ"""

test "MPQDecryptTable":
  var t = newMPQDecryptTable()
  check t[0] == 1439053538'u32
  doAssert t[100] == 2690928833'u32
  doAssert t[245] == 2149902055'u32

test "MPQHashString":
  var r = mpqHashString("(hash table)", MPQHashType.tableKey)
  check r == 3283040112'u32

test "func decryptTable":
  var data = "12345678"
  mpqDecryptTable(data, "(hash table)")
  check int(data[0]) == 253
  check int(data[1]) == 253
  check int(data[2]) == 15
  check int(data[3]) == 178
  check int(data[4]) == 224
  check int(data[5]) == 18
  check int(data[6]) == 234
  check int(data[7]) == 33

# test "init mpq":
#   var mpq = newMPQ(testFile)
#   check mpq != nil
#   mpq.free()

# test "init mpq 2":
#   var mpq = newMPQ(testFile2)
#   check mpq != nil
#   mpq.free()

test "init mpq 3":
  var mpq = newMPQ(testFile3)
  check mpq != nil
  mpq.free()

test "readFile ":
  var mpq = newMPQ(testFile3)
  check mpq != nil
  var size: uint32 = 0
  var flags: uint32 = 0
  mpq.getFileInfo("(listfile)", size, flags)
  flags.dumpFlags()
  echo "Size - ", size, " flags - ", flags

  mpq.getFileInfo("Interface\\GLUES\\Credits\\1024px-Blade3_final1.blp", size, flags)
  flags.dumpFlags()
  echo "Size - ", size, " flags - ", flags
  # echo "Size - ", size

  # var file = mpq.readFile("Interface\\GLUES\\Credits\\1024px-Blade3_final1.blp")
  # echo cast[string](file.data)
test "listfiles":
  var mpq = newMPQ(testFile3)
  check mpq != nil
  var file2 = mpq.readFile("(listfile)")
  echo cast[string](file2.data)
  mpq.free()

test "BLP":
  var mpq = newMPQ(testFile3)
  check mpq != nil

  var file = mpq.readFile("""Interface\GLUES\Common\Glues-WoW-BCLogo.blp""")
  var texture = newBLPTextureFromData(file.data)

  discard existsOrCreateDir("test_output")
  echo savePNG32("test_output/logo.png", texture.getBitmap(), texture.header.width.int, texture.header.height.int)
  mpq.free()

test "BLP raw1 alpha 1":
  var mpq = newMPQ(testFile)
  check mpq != nil

  var file = mpq.readFile("""CHARACTER\Human\Female\HumanFemaleHairLongWavy.blp""")
  var texture = newBLPTextureFromData(file.data)

  discard existsOrCreateDir("test_output")
  echo savePNG32("test_output/HumanFemaleHairLongWavy.png", texture.getBitmap(), texture.header.width.int, texture.header.height.int)
  mpq.free()


test "all BLP to PNG files":
  var mpq = newMPQ(testFile)
  check mpq != nil

  var listfile = cast[string](mpq.readFile("(listfile)").data).splitLines
  for line in listfile:
    echo "blp ", line
    var sp = splitFile(line)
    if sp.ext != ".blp":
      continue

    var file = mpq.readFile(line)
    var texture = newBLPTextureFromData(file.data)

    discard existsOrCreateDir("test_output")
    echo savePNG32("test_output/" & splitFile(line).name & ".png", texture.getBitmap(), texture.header.width.int, texture.header.height.int)

  mpq.free()



# test "stress_test":
#   for i in 0 ..< 100:
#     var mpq = newMPQ(testFile3)
#     check mpq != nil
#     var size: uint32 = 0
#     var flags: uint32 = 0
#     mpq.getFileInfo("(listfile)", size, flags)
#     flags.dumpFlags()
#     echo "Size - ", size, " flags - ", flags

#     # mpq.getFileInfo("Interface\\GLUES\\Credits\\1024px-Blade3_final1.blp", size, flags)
#     # flags.dumpFlags()
#     # echo "Size - ", size

#     # var file = mpq.readFile("Interface\\GLUES\\Credits\\1024px-Blade3_final1.blp")
#     # echo cast[string](file.data)

#     var file2 = mpq.readFile("(listfile)")
#     echo cast[string](file2.data)
#     mpq.free()

# test "BLP2":
#   var mpq = newMPQ(testFile)
#   check mpq != nil

#   var file = mpq.readFile("""XTEXTURES\LAVA\lava.2.blp""")
#   var texture = newBLPTextureFromData(file.data)
