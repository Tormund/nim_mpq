# changed version of https://github.com/SoLaRGit/openS3TC

{.emit:
"""
//#include <stdio.h>

///////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2018 Nikola Bozovic. All rights reserved.
//
// This code is licensed under the MIT License (MIT).
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
///////////////////////////////////////////////////////////////////////////////
//
// openS3TC_DXT3
//
// version  : v2018.10.02
// author   : Nikola Bozovic <nigerija@gmail.com>
// desc     : optimized software DXT3 (BC2) texture block decompression.
// note     : S3TC patent expired on October 2, 2017.
//            And continuation patent expired on March 16, 2018.
//            S3TC support has landed in Mesa since then.
// changelog:
// * v2018.09.20: initial version.
//
// * v2018.09.23: optimized DXT3 (BC2) to use LUTs.
//
//   test 1920x1080 texture decode time on 3GHz CPU:
//      debug   : ~16.2 ms (vc2017 v141,vc2010 v100)
//        speed in :  ~128.0 mega bytes per sec
//        speed out:  ~512.0 mega bytes per sec
//        speed pix:  ~128.0 mega pixels per sec
//      release :  ~8.0 ms (vc2017 v141)
//        speed in :  ~259.2 mega bytes per sec
//        speed out: ~1036.8 mega bytes per sec
//        speed pix:  ~259.2 mega pixels per sec
//      release :  ~7.3 ms (vc2010|vc2017 v100)
//        speed in :  ~284.0 mega bytes per sec
//        speed out: ~1136.2 mega bytes per sec
//        speed pix:  ~284.0 mega pixels per sec
//   yes there is difference if we are using platform toolset
//   vs2010|vs2017 v100 against vs2017 v141, v141 is slightly slower.
///////////////////////////////////////////////////////////////////////////////

typedef unsigned char     byte;
typedef unsigned short    ushort;
typedef unsigned int      uint;
typedef unsigned __int64  ulong;
#define null NULL

typedef enum DXT3PixelFormat
{
  /// <summary>4 byte texel:|B|G|R|A| (also default if incorrect pixel format specified.)</summary>
  DXT3PixelFormat_BGRA = 0,
  /// <summary>4 byte texel:|R|G|B|A|</summary>
  DXT3PixelFormat_RGBA = 1,
  /// <summary>4 byte texel:|A|R|G|B|</summary>
  DXT3PixelFormat_ARGB = 2,
  /// <summary>4 byte texel:|A|B|G|R|</summary>
  DXT3PixelFormat_ABGR = 3,
} DXT3PixelFormat;



#pragma region "### DXT3 defs and vars ###"

// total bytes in C2(R,G,B) LUT's    :   98304
// total bytes in ALPHA LUT's        : 2097152
// ---------------------------------------------------
// total bytes in luts               : 2195456

// DXT3 (BC2) defines color shifting for texels
DXT3PixelFormat __DXT3_LUT_OutPixelFormat = DXT3PixelFormat_BGRA;

// DXT3 (BC2) defines shifting in precalculated alpha
uint __DXT3_LUT_COLOR_SHIFT_A  = 24;

// DXT3 (BC2) defines shifting in precalculated [R,G,B] components
uint __DXT3_LUT_COLOR_SHIFT_R  = 16;
uint __DXT3_LUT_COLOR_SHIFT_G  = 8;
uint __DXT3_LUT_COLOR_SHIFT_B  = 0;

// DXT3 (BC2) pre calculated values for alpha codes
uint* __DXT3_LUT_COLOR_VALUE_A = NULL;

// DXT3 (BC2) precalculated [R,G,B] components for all 4 codes's
uint* __DXT3_LUT_COLOR_VALUE_R = NULL;
uint* __DXT3_LUT_COLOR_VALUE_G = NULL;
uint* __DXT3_LUT_COLOR_VALUE_B = NULL;

#pragma endregion

#pragma region "### DXT3 release internal memory ###"

// DXT3 (BC2) releases internal memory
void DXT3ReleaseLUTs()
{
  if (null != __DXT3_LUT_COLOR_VALUE_A)
  {
    free(__DXT3_LUT_COLOR_VALUE_A);
    __DXT3_LUT_COLOR_VALUE_A = null;
  }
  if (null != __DXT3_LUT_COLOR_VALUE_R)
  {
    free(__DXT3_LUT_COLOR_VALUE_R);
    __DXT3_LUT_COLOR_VALUE_R = null;
  }
  if (null != __DXT3_LUT_COLOR_VALUE_G)
  {
    free(__DXT3_LUT_COLOR_VALUE_G);
    __DXT3_LUT_COLOR_VALUE_B = null;
  }
  if (null != __DXT3_LUT_COLOR_VALUE_B)
  {
    free(__DXT3_LUT_COLOR_VALUE_B);
    __DXT3_LUT_COLOR_VALUE_B = null;
  }
}

#pragma endregion

#pragma region "### DXT3 build LUT(s) ###"

// builds static __DXT3_LUT_COLOR_VALUE_A[] look-up table
void __DXT3_LUT_COLOR_VALUE_A_Build()
{
  __DXT3_LUT_COLOR_VALUE_A = (uint*) malloc(64 * sizeof(uint));// uint[64]; // 8 * 256 * 256

  // DXT3 (BC2) pre calculated values for a codes
  byte __DXT3_LUT_8x8[16] = // 0x00 - 0x0f (0-15)
    {
        0,  17,  34,  51,  68,  85, 102, 119,
      136, 153, 170, 187, 204, 221, 238, 255
    };

  for (int i = 0; i <= 15; i++)
  {
    __DXT3_LUT_COLOR_VALUE_A[i] = __DXT3_LUT_8x8[i] << __DXT3_LUT_COLOR_SHIFT_A;
  }
}

// builds static __DXT3_LUT_COLOR_VALUE_RGB[R,G,B] look-up table's
void __DXT3_LUT_COLOR_VALUE_RGB_Build()
{
  // DXT3 (BC2) pre calculated values for r & b codes
  byte __DXT3_LUT_4x8[32] = // 0x00 - 0x1f (0-31)
    {
        0,   8,  16,  25,  33,  41,  49,  58,
       66,  74,  82,  90,  99, 107, 115, 123,
      132, 140, 148, 156, 164, 173, 181, 189,
      197, 205, 214, 222, 230, 238, 247, 255
    };

  // DXT3 (BC2) pre calculated values for g codes
  byte __DXT3_LUT_8x8[64] = // 0x00 - 0x3f (0-63)
    {
        0,   4,   8,  12,  16,  20,  24,  28,
       32,  36,  40,  45,  49,  53,  57,  61,
       65,  69,  73,  77,  81,  85,  89,  93,
       97, 101, 105, 109, 113, 117, 121, 125,
      130, 134, 138, 142, 146, 150, 154, 158,
      162, 166, 170, 174, 178, 182, 186, 190,
      194, 198, 202, 206, 210, 214, 219, 223,
      227, 231, 235, 239, 243, 247, 251, 255
    };

  __DXT3_LUT_COLOR_VALUE_R = (uint*) malloc(4096 * sizeof(uint));  // 4*32*32
  __DXT3_LUT_COLOR_VALUE_G = (uint*) malloc(16384 * sizeof(uint)); // 4*64*64
  __DXT3_LUT_COLOR_VALUE_B = (uint*) malloc(4096 * sizeof(uint));  // 4*32*32
  for (int cc0 = 0; cc0 < 32; cc0++)
  {
    for (int cc1 = 0; cc1 < 32; cc1++)
    {
      int index = ((cc0 << 5) | cc1) << 2;
      __DXT3_LUT_COLOR_VALUE_R[index | 0] = (uint)(((uint)__DXT3_LUT_4x8[cc0]) << __DXT3_LUT_COLOR_SHIFT_R);
      __DXT3_LUT_COLOR_VALUE_B[index | 0] = (uint)(((uint)__DXT3_LUT_4x8[cc0]) << __DXT3_LUT_COLOR_SHIFT_B);
      __DXT3_LUT_COLOR_VALUE_R[index | 1] = (uint)(((uint)__DXT3_LUT_4x8[cc1]) << __DXT3_LUT_COLOR_SHIFT_R);
      __DXT3_LUT_COLOR_VALUE_B[index | 1] = (uint)(((uint)__DXT3_LUT_4x8[cc1]) << __DXT3_LUT_COLOR_SHIFT_B);
      // Each RGB image data block is encoded according to the BC1 formats,
      // with the exception that the two code bits always use the non-transparent encodings.
      // In other words, they are treated as though color0 > color1,
      // regardless of the actual values of color0 and color1.
      // p2 = ((2*c0)+(c1))/3
      __DXT3_LUT_COLOR_VALUE_R[index | 2] = (uint)((uint)((byte)(((__DXT3_LUT_4x8[cc0] * 2) + (__DXT3_LUT_4x8[cc1])) / 3)) << __DXT3_LUT_COLOR_SHIFT_R);
      __DXT3_LUT_COLOR_VALUE_B[index | 2] = (uint)((uint)((byte)(((__DXT3_LUT_4x8[cc0] * 2) + (__DXT3_LUT_4x8[cc1])) / 3)) << __DXT3_LUT_COLOR_SHIFT_B);
      // p3 = ((c0)+(2*c1))/3
      __DXT3_LUT_COLOR_VALUE_R[index | 3] = (uint)((uint)((byte)(((__DXT3_LUT_4x8[cc0]) + (__DXT3_LUT_4x8[cc1] * 2)) / 3)) << __DXT3_LUT_COLOR_SHIFT_R);
      __DXT3_LUT_COLOR_VALUE_B[index | 3] = (uint)((uint)((byte)(((__DXT3_LUT_4x8[cc0]) + (__DXT3_LUT_4x8[cc1] * 2)) / 3)) << __DXT3_LUT_COLOR_SHIFT_B);
    }
  }
  for (int cc0 = 0; cc0 < 64; cc0++)
  {
    for (int cc1 = 0; cc1 < 64; cc1++)
    {
      int index = ((cc0 << 6) | cc1) << 2;
      __DXT3_LUT_COLOR_VALUE_G[index | 0] = (uint)(((uint)__DXT3_LUT_8x8[cc0]) << __DXT3_LUT_COLOR_SHIFT_G);
      __DXT3_LUT_COLOR_VALUE_G[index | 1] = (uint)(((uint)__DXT3_LUT_8x8[cc1]) << __DXT3_LUT_COLOR_SHIFT_G);
      // Each RGB image data block is encoded according to the BC1 formats,
      // with the exception that the two code bits always use the non-transparent encodings.
      // In other words, they are treated as though color0 > color1,
      // regardless of the actual values of color0 and color1.
      // p2 = ((2*c0)+(c1))/3
      __DXT3_LUT_COLOR_VALUE_G[index | 2] = (uint)((uint)((byte)(((__DXT3_LUT_8x8[cc0] * 2) + (__DXT3_LUT_8x8[cc1])) / 3)) << __DXT3_LUT_COLOR_SHIFT_G);
      // p3 = ((c0)+(2*c1))/3
      __DXT3_LUT_COLOR_VALUE_G[index | 3] = (uint)((uint)((byte)(((__DXT3_LUT_8x8[cc0]) + (__DXT3_LUT_8x8[cc1] * 2)) / 3)) << __DXT3_LUT_COLOR_SHIFT_G);
    }
  }
}

#pragma endregion

#pragma region "### DXT1 set output pixel format (rebuild LUTs if necessary) ###"

void DXT3SetOutputPixelFormat(DXT3PixelFormat pixelFormat)
{
  bool rebuildLut = (__DXT3_LUT_OutPixelFormat != pixelFormat);
  __DXT3_LUT_OutPixelFormat = pixelFormat;
  switch (__DXT3_LUT_OutPixelFormat)
  {
  case DXT3PixelFormat_ABGR:
    __DXT3_LUT_COLOR_SHIFT_A = 0;
    __DXT3_LUT_COLOR_SHIFT_B = 8;
    __DXT3_LUT_COLOR_SHIFT_G = 16;
    __DXT3_LUT_COLOR_SHIFT_R = 24;
    break;
  case DXT3PixelFormat_ARGB:
    __DXT3_LUT_COLOR_SHIFT_A = 0;
    __DXT3_LUT_COLOR_SHIFT_R = 8;
    __DXT3_LUT_COLOR_SHIFT_G = 16;
    __DXT3_LUT_COLOR_SHIFT_B = 24;
    break;
  case DXT3PixelFormat_RGBA:
    __DXT3_LUT_COLOR_SHIFT_R = 0;
    __DXT3_LUT_COLOR_SHIFT_G = 8;
    __DXT3_LUT_COLOR_SHIFT_B = 16;
    __DXT3_LUT_COLOR_SHIFT_A = 24;
    break;
  case DXT3PixelFormat_BGRA:
  default:
    __DXT3_LUT_COLOR_SHIFT_B = 0;
    __DXT3_LUT_COLOR_SHIFT_G = 8;
    __DXT3_LUT_COLOR_SHIFT_R = 16;
    __DXT3_LUT_COLOR_SHIFT_A = 24;
    break;
  }
  if (rebuildLut || null == __DXT3_LUT_COLOR_VALUE_R)
  {
    __DXT3_LUT_COLOR_VALUE_A_Build();
    __DXT3_LUT_COLOR_VALUE_RGB_Build();
  }
}

#pragma endregion

#pragma region "### DXT3 decompress exported function ###"

/// <summary>
/// Decompresses all the blocks of a DXT1 (BC1) compressed texture and stores the resulting pixels in 'image'.
/// </summary>
/// <param name="width">Texture width.</param>
/// <param name="height">Texture height.</param>
/// <param name="p_input">pointer to compressed DXT1 blocks.</param>
/// <param name="p_output">pointer to the image where the decoded pixels will be stored.</param>
void DXT3Decompress(uint width, uint height, byte* p_input, byte* p_output)
{
  if (NULL == __DXT3_LUT_COLOR_VALUE_A)
  {
    __DXT3_LUT_COLOR_VALUE_A_Build();
    __DXT3_LUT_COLOR_VALUE_RGB_Build();
  }

  // direct copy paste from c# code, not even comments changed

  byte* source = (byte*)p_input;
  uint* target = (uint*)p_output;
  uint target_4scans = (width << 2);
  uint x_block_count = (width + 3) >> 2;
  uint y_block_count = (height + 3) >> 2;

  //############################################################
  if ((x_block_count << 2) != width || (y_block_count << 2) != height)
  {
    uint* EOI = target + (width * height);
    // target : advance by 4 scan lines
    for (uint y_block = 0; y_block < y_block_count; y_block++, target += target_4scans)
    {
        uint* texel_x = target;
        // texel: advance by 4 texels
        for (uint x_block = 0; x_block < x_block_count; x_block++, source += 16, texel_x += 4)
        {
        // read DXT3 (BC2) block datas
        ulong aclut = *(ulong*)(source);        // 00-07 : a LUT    (64bits) 4x4x4bits
        ushort cc0 = *(ushort*)(source + 8);    // 08-09 : cc0      (16bits)
        ushort cc1 = *(ushort*)(source + 10);   // 0a-0b : cc1      (16bits)
        uint ccfnlut = *(uint*)(source + 12);   // 0c-0f : ccfn LUT (32bits) 4x4x2bits

        // alpha code and color code [r,g,b] indexes to lut values
        uint ccr = ((uint)((cc0 & 0xf800) >> 4) | (uint)((cc1 & 0xf800) >> 9));
        uint ccg = ((uint)((cc0 & 0x07E0) << 3) | (uint)((cc1 & 0x07E0) >> 3));
        uint ccb = ((uint)((cc0 & 0x001F) << 7) | (uint)((cc1 & 0x001F) << 2));

        // process 4x4 texels
        uint* texel = texel_x;
        for (uint by = 0; by < 4; by++, texel += width)
        {
            //############################################################
            // Check Y Bound (break: no more texels available for block)
            if (texel >= EOI) break;
            //############################################################
            for (uint bx = 0; bx < 4; bx++, aclut >>= 4, ccfnlut >>= 2)
            {
            //############################################################
            // Check X Bound (continue: need ac|ccfnlut to complete shift)
            if (texel + bx >= EOI) continue;
            //############################################################
            uint ac = (uint)(aclut & 0x0f);
            uint ccfn = (uint)(ccfnlut & 0x03);

            *(texel + bx) = (uint)
                (
                __DXT3_LUT_COLOR_VALUE_A[ac] |
                __DXT3_LUT_COLOR_VALUE_R[ccr|ccfn] |
                __DXT3_LUT_COLOR_VALUE_G[ccg|ccfn] |
                __DXT3_LUT_COLOR_VALUE_B[ccb|ccfn]
                );
            }//bx
        }//by
        }//x_block
    }//y_block
    return;
  }
  //############################################################
  //ProcessWithoutCheckingTexelBounds:
  //
  // NOTICE: source and target ARE aligned as 4x4 texels
  //
  // target : advance by 4 scan lines
  for (uint y_block = 0; y_block < y_block_count; y_block++, target+=target_4scans)
  {
    // texel: advance by 4 texels
    uint* texel_x = target;
    for (uint x_block = 0; x_block < x_block_count; x_block++, source+=16, texel_x+=4)
    {
      // read DXT3 (BC2) block data
      ulong aclut = *(ulong*)(source);        // 00-07 : a LUT    (64bits) 4x4x4bits
      ushort cc0 = *(ushort*)(source + 8);    // 08-09 : cc0      (16bits)
      ushort cc1 = *(ushort*)(source + 10);   // 0a-0b : cc1      (16bits)
      uint ccfnlut = *(uint*)(source + 12);   // 0c-0f : ccfn LUT (32bits) 4x4x2bits

      // alpha code and color code [r,g,b] indexes to luts
      uint ccr = ((uint)((cc0 & 0xf800) >> 4) | (uint)((cc1 & 0xf800) >> 9));
      uint ccg = ((uint)((cc0 & 0x07E0) << 3) | (uint)((cc1 & 0x07E0) >> 3));
      uint ccb = ((uint)((cc0 & 0x001F) << 7) | (uint)((cc1 & 0x001F) << 2));

      // process 4x4 color code
      uint* texel = texel_x;
      for (uint by = 0; by < 4; by++, texel += width)
      {
        // TODO: need to test the order of bits in ac

        for (uint bx = 0; bx < 4; bx++, aclut>>=4, ccfnlut>>=2)
        {

          // TODO: need to test the order of bits in ac
          uint ac = (uint)(aclut & 0x0f);
          uint ccfn = (uint)(ccfnlut & 0x03);

          *(texel + bx) = (uint)
            (
              __DXT3_LUT_COLOR_VALUE_A[ac] |
              __DXT3_LUT_COLOR_VALUE_R[ccr | ccfn] |
              __DXT3_LUT_COLOR_VALUE_G[ccg | ccfn] |
              __DXT3_LUT_COLOR_VALUE_B[ccb | ccfn]
            );
        }//bx
      }//by
    }//x_block
  }//y_block
	return;
  //
  //############################################################
  // NOTICE: source and target ARE NOT aligned to 4x4 texels,
  //         We must check for End Of Image (EOI) in this case.
  //############################################################
  // lazy to write boundary separate processings.
  // Just end of image (EOI) pointer check only.
  // considering that I have encountered few images that are not
  // aligned to 4x4 texels, this should be almost never called.
  // takes ~500us (0.5ms) more time processing 2MB pixel images.
  //############################################################
  //
}

typedef enum DXT1PixelFormat
{
  /// <summary>4 byte texel:|B|G|R|A| (also default if incorrect pixel format specified.)</summary>
  DXT1PixelFormat_BGRA = 0,
  /// <summary>4 byte texel:|R|G|B|A|</summary>
  DXT1PixelFormat_RGBA = 1,
  /// <summary>4 byte texel:|A|R|G|B|</summary>
  DXT1PixelFormat_ARGB = 2,
  /// <summary>4 byte texel:|A|B|G|R|</summary>
  DXT1PixelFormat_ABGR = 3,
} DXT1PixelFormat;

// total bytes in COLOR(A,R,G,B) static LUT's :   196608

//forward declarations
void __DXT1_LUT_Build();

DXT1PixelFormat __DXT1_LUT_OutPixelFormat = DXT1PixelFormat_BGRA;

// DXT1 (BC1) defines shifting in precalculated alpha
uint __DXT1_LUT_COLOR_SHIFT_A  = 24;
// DXT1 (BC1) defines shifting in precalculated [R,G,B] components
uint __DXT1_LUT_COLOR_SHIFT_R  = 16;
uint __DXT1_LUT_COLOR_SHIFT_G  = 8;
uint __DXT1_LUT_COLOR_SHIFT_B  = 0;

// DXT1 (BC1) pre calculated values for alpha codes
uint __DXT1_LUT_COLOR_VALUE_A = (uint)(0xff << 24);

// DXT1 (BC1) precalculated [R,G,B] components for all 4 codes's
uint* __DXT1_LUT_COLOR_VALUE_R = null;
uint* __DXT1_LUT_COLOR_VALUE_G = null;
uint* __DXT1_LUT_COLOR_VALUE_B = null;

#pragma endregion

// DXT1 (BC1) releases internal memory
void DXT1ReleaseLUTs()
{
  if (null != __DXT1_LUT_COLOR_VALUE_R)
  {
   free(__DXT1_LUT_COLOR_VALUE_R);
    __DXT1_LUT_COLOR_VALUE_R = null;
  }
  if (null != __DXT1_LUT_COLOR_VALUE_G)
  {
   free(__DXT1_LUT_COLOR_VALUE_G);
    __DXT1_LUT_COLOR_VALUE_G = null;
  }
  if (null != __DXT1_LUT_COLOR_VALUE_B)
  {
   free(__DXT1_LUT_COLOR_VALUE_B);
    __DXT1_LUT_COLOR_VALUE_B = null;
  }
}

#pragma region "### DXT1 set output pixel format (rebuild LUTs if necessary) ###"

void DXT1SetOutputPixelFormat(DXT1PixelFormat pixelFormat)
{
  bool rebuildLut = (__DXT1_LUT_OutPixelFormat != pixelFormat);
  __DXT1_LUT_OutPixelFormat = pixelFormat;
  switch (__DXT1_LUT_OutPixelFormat)
  {
  case DXT1PixelFormat_ABGR:
    __DXT1_LUT_COLOR_SHIFT_A = 0;
    __DXT1_LUT_COLOR_SHIFT_B = 8;
    __DXT1_LUT_COLOR_SHIFT_G = 16;
    __DXT1_LUT_COLOR_SHIFT_R = 24;
    break;
  case DXT1PixelFormat_ARGB:
    __DXT1_LUT_COLOR_SHIFT_A = 0;
    __DXT1_LUT_COLOR_SHIFT_R = 8;
    __DXT1_LUT_COLOR_SHIFT_G = 16;
    __DXT1_LUT_COLOR_SHIFT_B = 24;
    break;
  case DXT1PixelFormat_RGBA:
    __DXT1_LUT_COLOR_SHIFT_R = 0;
    __DXT1_LUT_COLOR_SHIFT_G = 8;
    __DXT1_LUT_COLOR_SHIFT_B = 16;
    __DXT1_LUT_COLOR_SHIFT_A = 24;
    break;
  case DXT1PixelFormat_BGRA:
  default:
    __DXT1_LUT_COLOR_SHIFT_B = 0;
    __DXT1_LUT_COLOR_SHIFT_G = 8;
    __DXT1_LUT_COLOR_SHIFT_R = 16;
    __DXT1_LUT_COLOR_SHIFT_A = 24;
    break;
  }
  if (rebuildLut || null == __DXT1_LUT_COLOR_VALUE_R)
  {
    __DXT1_LUT_Build();
  }
}

#pragma endregion

#pragma region "### DXT1 build LUTs ###"

// builds static Build_LUT_DXT1_COLOR_[R,G,B] look-up table's
void __DXT1_LUT_Build()
{
  // DXT1 (BC1) pre calculated values for r & b codes
  byte __LUT_DXT1_4x8[32] = // 0x00 - 0x1f (0-31)
    {
        0,   8,  16,  25,  33,  41,  49,  58,
       66,  74,  82,  90,  99, 107, 115, 123,
      132, 140, 148, 156, 164, 173, 181, 189,
      197, 205, 214, 222, 230, 238, 247, 255
    };

  // DXT1 (BC1) pre calculated values for g codes
  byte __LUT_DXT1_8x8[64] = // 0x00 - 0x3f (0-63)
    {
        0,   4,   8,  12,  16,  20,  24,  28,
       32,  36,  40,  45,  49,  53,  57,  61,
       65,  69,  73,  77,  81,  85,  89,  93,
       97, 101, 105, 109, 113, 117, 121, 125,
      130, 134, 138, 142, 146, 150, 154, 158,
      162, 166, 170, 174, 178, 182, 186, 190,
      194, 198, 202, 206, 210, 214, 219, 223,
      227, 231, 235, 239, 243, 247, 251, 255
    };

  __DXT1_LUT_COLOR_VALUE_A = (uint) ((uint)0xFF << __DXT1_LUT_COLOR_SHIFT_A);
  if (null == __DXT1_LUT_COLOR_VALUE_R)
  {
    __DXT1_LUT_COLOR_VALUE_R = (uint*) malloc(8192 * sizeof(uint));  // 4*2*32*32 (4:code)*(2:alpha)*(32:c0(r)matrix4x8)*(32:c1(r)matrix4x8)
    __DXT1_LUT_COLOR_VALUE_G = (uint*) malloc(32768 * sizeof(uint)); // 4*2*64*64 (4:code)*(2:alpha)*(64:c0(g)matrix8x8)*(64:c1(g)matrix8x8)
    __DXT1_LUT_COLOR_VALUE_B = (uint*) malloc(8192 * sizeof(uint));  // 4*2*32*32 (4:code)*(2:alpha)*(32:c0(b)matrix4x8)*(32:c1(b)matrix4x8)
  }

  for (int ac = 0; ac <= 1; ac++)
  {
    for (int cc0 = 0; cc0 < 32; cc0++)
    {
      for (int cc1 = 0; cc1 < 32; cc1++)
      {
        int index = ((cc0 << 6) | (cc1 << 1) | (ac)) << 2; // 2 bits for ccfn
        __DXT1_LUT_COLOR_VALUE_R[index | 0] = __DXT1_LUT_COLOR_VALUE_A | (uint)(((uint)__LUT_DXT1_4x8[cc0]) << __DXT1_LUT_COLOR_SHIFT_R);
        __DXT1_LUT_COLOR_VALUE_B[index | 0] = __DXT1_LUT_COLOR_VALUE_A | (uint)(((uint)__LUT_DXT1_4x8[cc0]) << __DXT1_LUT_COLOR_SHIFT_B);
        __DXT1_LUT_COLOR_VALUE_R[index | 1] = __DXT1_LUT_COLOR_VALUE_A | (uint)(((uint)__LUT_DXT1_4x8[cc1]) << __DXT1_LUT_COLOR_SHIFT_R);
        __DXT1_LUT_COLOR_VALUE_B[index | 1] = __DXT1_LUT_COLOR_VALUE_A | (uint)(((uint)__LUT_DXT1_4x8[cc1]) << __DXT1_LUT_COLOR_SHIFT_B);
        if (cc0 > cc1)
        {
          // p2 = ((2*c0)+(c1))/3
          __DXT1_LUT_COLOR_VALUE_R[index | 2] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_4x8[cc0] * 2) + (__LUT_DXT1_4x8[cc1])) / 3)) << __DXT1_LUT_COLOR_SHIFT_R);
          __DXT1_LUT_COLOR_VALUE_B[index | 2] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_4x8[cc0] * 2) + (__LUT_DXT1_4x8[cc1])) / 3)) << __DXT1_LUT_COLOR_SHIFT_B);
          // p3 = ((c0)+(2*c1))/3
          __DXT1_LUT_COLOR_VALUE_R[index | 3] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_4x8[cc0]) + (__LUT_DXT1_4x8[cc1] * 2)) / 3)) << __DXT1_LUT_COLOR_SHIFT_R);
          __DXT1_LUT_COLOR_VALUE_B[index | 3] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_4x8[cc0]) + (__LUT_DXT1_4x8[cc1] * 2)) / 3)) << __DXT1_LUT_COLOR_SHIFT_B);
        }
        else // c0 <= c1
        {
          // p2 = (c0/2)+(c1/2)
          __DXT1_LUT_COLOR_VALUE_R[index | 2] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_4x8[cc0] / 2) + (__LUT_DXT1_4x8[cc1] / 2)))) << __DXT1_LUT_COLOR_SHIFT_R);
          __DXT1_LUT_COLOR_VALUE_B[index | 2] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_4x8[cc0] / 2) + (__LUT_DXT1_4x8[cc1] / 2)))) << __DXT1_LUT_COLOR_SHIFT_B);
          if (ac == 0)
          {
            // p3 = (color0 + 2*color1) / 3
            __DXT1_LUT_COLOR_VALUE_R[index | 3] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_4x8[cc0]) + (__LUT_DXT1_4x8[cc1] * 2)) / 3)) << __DXT1_LUT_COLOR_SHIFT_R);
            __DXT1_LUT_COLOR_VALUE_B[index | 3] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_4x8[cc0]) + (__LUT_DXT1_4x8[cc1] * 2)) / 3)) << __DXT1_LUT_COLOR_SHIFT_B);
          }
          else // tr == 1
          {
            // p3 == 0
            __DXT1_LUT_COLOR_VALUE_R[index | 3] = 0; // transparent black
            __DXT1_LUT_COLOR_VALUE_B[index | 3] = 0; // transparent black
          }
        }
      }//cc1
    }//cc0
  }//ac
  for (int ac = 0; ac <= 1; ac++)
  {
    for (int cc0 = 0; cc0 < 64; cc0++)
    {
      for (int cc1 = 0; cc1 < 64; cc1++)
      {
        int index = ((cc0 << 7) | (cc1 << 1) | (ac)) << 2; // 2 bits for ccfn
        __DXT1_LUT_COLOR_VALUE_G[index | 0] = __DXT1_LUT_COLOR_VALUE_A | (uint)(((uint)__LUT_DXT1_8x8[cc0]) << __DXT1_LUT_COLOR_SHIFT_G);
        __DXT1_LUT_COLOR_VALUE_G[index | 1] = __DXT1_LUT_COLOR_VALUE_A | (uint)(((uint)__LUT_DXT1_8x8[cc1]) << __DXT1_LUT_COLOR_SHIFT_G);
        if (cc0 > cc1)
        {
          // p2 = ((2*c0)+(c1))/3
          __DXT1_LUT_COLOR_VALUE_G[index | 2] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_8x8[cc0] * 2) + (__LUT_DXT1_8x8[cc1])) / 3)) << __DXT1_LUT_COLOR_SHIFT_G);
          // p3 = ((c0)+(2*c1))/3
          __DXT1_LUT_COLOR_VALUE_G[index | 3] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_8x8[cc0]) + (__LUT_DXT1_8x8[cc1] * 2)) / 3)) << __DXT1_LUT_COLOR_SHIFT_G);
        }
        else // c0 <= c1
        {
          // p2 = (c0/2)+(c1/2)
          __DXT1_LUT_COLOR_VALUE_G[index | 2] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_8x8[cc0] / 2) + (__LUT_DXT1_8x8[cc1]) / 2))) << __DXT1_LUT_COLOR_SHIFT_G);
          if (ac == 0)
          {
            // p3 = (color0 + 2*color1) / 3
            __DXT1_LUT_COLOR_VALUE_G[index | 3] = __DXT1_LUT_COLOR_VALUE_A | (uint)((uint)((byte)(((__LUT_DXT1_8x8[cc0] / 2) + (__LUT_DXT1_8x8[cc1]) / 2))) << __DXT1_LUT_COLOR_SHIFT_G);
          }
          else
          {
            // p3 == 0
            __DXT1_LUT_COLOR_VALUE_G[index | 3] = 0; // transparent black
          }
        }
      }//cc1
    }//cc0
  }//ac
}
#pragma endregion

#pragma region "### DXT1 decompress ###"

/// <summary>
/// Decompresses all the blocks of a DXT1 (BC1) compressed texture and stores the resulting pixels in 'image'.
/// </summary>
/// <param name="width">Texture width.</param>
/// <param name="height">Texture height.</param>
/// <param name="p_input">pointer to compressed DXT1 blocks.</param>
/// <param name="p_output">pointer to the image where the decompressed pixels will be stored.</param>
void DXT1Decompress(uint width, uint height, byte* p_input, byte* p_output)
{
  if (NULL == __DXT1_LUT_COLOR_VALUE_R)
  {
    __DXT1_LUT_Build();
  }

  // direct copy paste from c# code, not even comments changed

  byte* source = (byte*)p_input; // block size: 64bit
  uint* target = (uint*)p_output;
  uint target_4scans = (width << 2);
  uint x_block_count = (width + 3) / 4;
  uint y_block_count = (height + 3) / 4;

  if (x_block_count * 4 != width || y_block_count * 4 != height)
  {
    // for images that do not fit in 4x4 texel bounds

    //
    // NOTICE: source and target ARE NOT aligned to 4x4 texels,
    //         We must check for End Of Image (EOI) in this case.
    //
    // lazy to write boundary separate processings.
    // Just end of image (EOI) pointer check only.
    // considering that I haven't encountered any image that is not
    // aligned to 4x4 texel this almost never should be called.
    // and takes 0.5~1 ms more time processing 2MB pixel images.
    //
    uint* EOI = target + (width * height);
    // target : advance by 4 scan lines
    for (uint y_block = 0; y_block < y_block_count; y_block++, target += target_4scans)
    {
      uint* texel_x = target;
      // texel: advance by 4 texels
      for (uint x_block = 0; x_block < x_block_count; x_block++, source += 8, texel_x += 4)
      {
        // read DXT1 (BC1) block data
        ushort cc0 = *(ushort*)(source);      // 00-01 : cc0       (16bits)
        ushort cc1 = *(ushort*)(source + 2);  // 02-03 : cc1       (16bits)
        uint ccfnlut = *(uint*)(source + 4);  // 04-07 : ccfn LUT  (32bits) 4x4x2bits
        uint ac = (uint)(cc0 > cc1 ? 0 : 4);

        // color code [r,g,b] indexes to lut(s)
        uint ccr = ((uint)((cc0 & 0xf800) >> 3) | (uint)((cc1 & 0xf800) >> 8)) | ac;
        uint ccg = ((uint)((cc0 & 0x07E0) << 4) | (uint)((cc1 & 0x07E0) >> 2)) | ac;
        uint ccb = ((uint)((cc0 & 0x001F) << 8) | (uint)((cc1 & 0x001F) << 3)) | ac;

        // process 4x4 texels
        uint* texel = texel_x;
        for (uint by = 0; by < 4; by++, texel += width) // next line
        {
          //############################################################
          // Check Y Bound (break: no more texels available for block)
          if (texel >= EOI) break;
          //############################################################
          for (int bx = 0; bx < 4; bx++, ccfnlut >>= 2)
          {
            //############################################################
            // Check X Bound (continue: need ccfnlut to complete shift)
            if (texel + bx >= EOI) continue;
            //############################################################
            uint ccfn = (ccfnlut & 0x03);

            *(texel + bx) = (uint)
              (
                __DXT1_LUT_COLOR_VALUE_R[ccr | ccfn] |
                __DXT1_LUT_COLOR_VALUE_G[ccg | ccfn] |
                __DXT1_LUT_COLOR_VALUE_B[ccb | ccfn]
              );
          }//bx
        }//by
      }//x_block
    }//y_block
  return;
  }

  // NOTICE: source and target ARE aligned as 4x4 texels

  // target : advance by 4 scan lines
  for (uint y_block = 0; y_block < y_block_count; y_block++, target+=target_4scans)
  {
    // texel: advance by 4 texels
    uint* texel_x = target;
    for (uint x_block = 0; x_block < x_block_count; x_block++, source+=8, texel_x+=4)
    {
      // read DXT1 (BC1) block data
      ushort cc0 = *(ushort*)(source);      // 00-01 : cc0       (16bits)
      ushort cc1 = *(ushort*)(source + 2);  // 02-03 : cc1       (16bits)
      uint ccfnlut = *(uint*)(source + 4);  // 04-07 : ccfn LUT  (32bits) 4x4x2bits
      uint ac = (uint)(cc0 > cc1 ? 0 : 4);

      // color code [r,g,b] indexes to luts
      uint ccr = ((uint)((cc0 & 0xf800) >> 3) | (uint)((cc1 & 0xf800) >> 8)) | ac;
      uint ccg = ((uint)((cc0 & 0x07E0) << 4) | (uint)((cc1 & 0x07E0) >> 2)) | ac;
      uint ccb = ((uint)((cc0 & 0x001F) << 8) | (uint)((cc1 & 0x001F) << 3)) | ac;

      // process 4x4 texels
      uint* texel = texel_x;
      for (uint by = 0; by < 4; by++, texel += width) // next line
      {
        for (int bx = 0; bx < 4; bx++, ccfnlut >>= 2)
        {
          uint ccfn = (ccfnlut & 0x03);

          *(texel + bx) = (uint)
            (
              __DXT1_LUT_COLOR_VALUE_R[ccr | ccfn] |
              __DXT1_LUT_COLOR_VALUE_G[ccg | ccfn] |
              __DXT1_LUT_COLOR_VALUE_B[ccb | ccfn]
            );
        }//bx
      }//by
    }//x_block
  }//y_block
  return;
}


typedef enum DXT5PixelFormat
{
  /// <summary>4 byte texel:|B|G|R|A| (also default if incorrect pixel format specified.)</summary>
  DXT5PixelFormat_BGRA = 0,
  /// <summary>4 byte texel:|R|G|B|A|</summary>
  DXT5PixelFormat_RGBA = 1,
  /// <summary>4 byte texel:|A|R|G|B|</summary>
  DXT5PixelFormat_ARGB = 2,
  /// <summary>4 byte texel:|A|B|G|R|</summary>
  DXT5PixelFormat_ABGR = 3,
} DXT5PixelFormat;


#pragma region "### DXT5 defs and vars ###"

// total bytes in C2(R,G,B) LUT's    :   98304
// total bytes in ALPHA LUT's        : 2097152
// ---------------------------------------------------
// total bytes in luts               : 2195456

// DXT5 (BC3) defines color shifting for texels
DXT5PixelFormat __DXT5_LUT_OutPixelFormat = DXT5PixelFormat_BGRA;

// DXT5 (BC3) defines shifting in precalculated alpha
uint __DXT5_LUT_COLOR_SHIFT_A  = 24;

// DXT5 (BC3) defines shifting in precalculated [R,G,B] components
uint __DXT5_LUT_COLOR_SHIFT_R  = 16;
uint __DXT5_LUT_COLOR_SHIFT_G  = 8;
uint __DXT5_LUT_COLOR_SHIFT_B  = 0;

// DXT5 (BC3) pre calculated values for alpha codes
uint* __DXT5_LUT_COLOR_VALUE_A = NULL;

// DXT5 (BC3) precalculated [R,G,B] components for all 4 codes's
uint* __DXT5_LUT_COLOR_VALUE_R = NULL;
uint* __DXT5_LUT_COLOR_VALUE_G = NULL;
uint* __DXT5_LUT_COLOR_VALUE_B = NULL;

#pragma endregion

#pragma region "### DXT5 release internal memory ###"

// DXT5 (BC3) releases internal memory
void DXT5ReleaseLUTs()
{
  if (null != __DXT5_LUT_COLOR_VALUE_A)
  {
    free(__DXT5_LUT_COLOR_VALUE_A);
    __DXT5_LUT_COLOR_VALUE_A = null;
  }
  if (null != __DXT5_LUT_COLOR_VALUE_R)
  {
    free(__DXT5_LUT_COLOR_VALUE_R);
    __DXT5_LUT_COLOR_VALUE_R = null;
  }
  if (null != __DXT5_LUT_COLOR_VALUE_G)
  {
    free(__DXT5_LUT_COLOR_VALUE_G);
    __DXT5_LUT_COLOR_VALUE_B = null;
  }
  if (null != __DXT5_LUT_COLOR_VALUE_B)
  {
    free(__DXT5_LUT_COLOR_VALUE_B);
    __DXT5_LUT_COLOR_VALUE_B = null;
  }
}

#pragma endregion

#pragma region "### DXT5 build LUT(s) ###"

// builds static __DXT5_LUT_COLOR_VALUE_A[] look-up table
void __DXT5_LUT_COLOR_VALUE_A_Build()
{
  __DXT5_LUT_COLOR_VALUE_A = (uint*)malloc(524288 * sizeof(uint)); // 8 * 256 * 256
  // where a[0..7]
  for (int a = 0; a <= 7; a++)
  {
    // where a0[0..255]
    for (int a0 = 0; a0 <= 255; a0++)
    {
      // where a1[0..255]
      for (int a1 = 0; a1 <= 255; a1++)
      {
        // if (a0 > a1) deliberatelly moved inside switch(a) so it can be switch jump optimized execution
        int index = (a0 << 3) | (a1 << 11) | (a);
        switch (a)
        {
          case 0:
            __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)a0 << __DXT5_LUT_COLOR_SHIFT_A);
            break;
          case 1:
            __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)a1 << __DXT5_LUT_COLOR_SHIFT_A);
            break;
          case 2:
            if (a0 > a1)
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)(((6 * a0) + (/**/a1)) / 7) << __DXT5_LUT_COLOR_SHIFT_A);
            else
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)(((4 * a0) + (/**/a1)) / 5) << __DXT5_LUT_COLOR_SHIFT_A);
            break;
          case 3:
            if (a0 > a1)
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)(((5 * a0) + (2 * a1)) / 7) << __DXT5_LUT_COLOR_SHIFT_A);
            else
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)(((3 * a0) + (2 * a1)) / 5) << __DXT5_LUT_COLOR_SHIFT_A);
            break;
          case 4:
            if (a0 > a1)
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)(((4 * a0) + (3 * a1)) / 7) << __DXT5_LUT_COLOR_SHIFT_A);
            else
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)(((2 * a0) + (3 * a1)) / 5) << __DXT5_LUT_COLOR_SHIFT_A);
            break;
          case 5:
            if (a0 > a1)
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)(((3 * a0) + (4 * a1)) / 7)) << __DXT5_LUT_COLOR_SHIFT_A;
            else
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)(((/**/a0) + (4 * a1)) / 5)) << __DXT5_LUT_COLOR_SHIFT_A;
            break;
          case 6:
            if (a0 > a1)
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((byte)(((2 * a0) + (5 * a1)) / 7)) << __DXT5_LUT_COLOR_SHIFT_A;
            else
              __DXT5_LUT_COLOR_VALUE_A[index] = 0;  // __DXT5_LUT_COLOR_SHIFT_A // no point
            break;
          case 7:
            if (a0 > a1)
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)(((byte)(((/**/a0) + (6 * a1)) / 7)) << __DXT5_LUT_COLOR_SHIFT_A);
            else
              __DXT5_LUT_COLOR_VALUE_A[index] = (uint)((255) << __DXT5_LUT_COLOR_SHIFT_A);
            break;
        }// switch(a)
      } // a1
    } // a0
  } // a
}

// builds static __DXT5_LUT_COLOR_VALUE_RGB[R,G,B] look-up table's
void __DXT5_LUT_COLOR_VALUE_RGB_Build()
{
  // DXT5 (BC3) pre calculated values for r & b codes
  byte __DXT5_LUT_4x8[32] = // 0x00 - 0x1f (0-31)
    {
        0,   8,  16,  25,  33,  41,  49,  58,
       66,  74,  82,  90,  99, 107, 115, 123,
      132, 140, 148, 156, 164, 173, 181, 189,
      197, 205, 214, 222, 230, 238, 247, 255
    };

  // DXT5 (BC3) pre calculated values for g codes
  byte __DXT5_LUT_8x8[64] = // 0x00 - 0x3f (0-63)
    {
        0,   4,   8,  12,  16,  20,  24,  28,
       32,  36,  40,  45,  49,  53,  57,  61,
       65,  69,  73,  77,  81,  85,  89,  93,
       97, 101, 105, 109, 113, 117, 121, 125,
      130, 134, 138, 142, 146, 150, 154, 158,
      162, 166, 170, 174, 178, 182, 186, 190,
      194, 198, 202, 206, 210, 214, 219, 223,
      227, 231, 235, 239, 243, 247, 251, 255
    };

  __DXT5_LUT_COLOR_VALUE_R = (uint*) malloc(sizeof(uint) * 4096);  // 4*32*32
  __DXT5_LUT_COLOR_VALUE_G = (uint*) malloc(sizeof(uint) * 16384); // 4*64*64
  __DXT5_LUT_COLOR_VALUE_B = (uint*) malloc(sizeof(uint) * 4096);  // 4*32*32

  for (int cc0 = 0; cc0 < 32; cc0++)
  {
    for (int cc1 = 0; cc1 < 32; cc1++)
    {
      int index = ((cc0 << 5) | cc1) << 2;
      __DXT5_LUT_COLOR_VALUE_R[index | 0] = (uint)(((uint)__DXT5_LUT_4x8[cc0]) << __DXT5_LUT_COLOR_SHIFT_R);
      __DXT5_LUT_COLOR_VALUE_B[index | 0] = (uint)(((uint)__DXT5_LUT_4x8[cc0]) << __DXT5_LUT_COLOR_SHIFT_B);
      __DXT5_LUT_COLOR_VALUE_R[index | 1] = (uint)(((uint)__DXT5_LUT_4x8[cc1]) << __DXT5_LUT_COLOR_SHIFT_R);
      __DXT5_LUT_COLOR_VALUE_B[index | 1] = (uint)(((uint)__DXT5_LUT_4x8[cc1]) << __DXT5_LUT_COLOR_SHIFT_B);
      // Each RGB image data block is encoded according to the BC1 formats,
      // with the exception that the two code bits always use the non-transparent encodings.
      // In other words, they are treated as though color0 > color1,
      // regardless of the actual values of color0 and color1.
      // p2 = ((2*c0)+(c1))/3
      __DXT5_LUT_COLOR_VALUE_R[index | 2] = (uint)((uint)((byte)(((__DXT5_LUT_4x8[cc0] * 2) + (__DXT5_LUT_4x8[cc1])) / 3)) << __DXT5_LUT_COLOR_SHIFT_R);
      __DXT5_LUT_COLOR_VALUE_B[index | 2] = (uint)((uint)((byte)(((__DXT5_LUT_4x8[cc0] * 2) + (__DXT5_LUT_4x8[cc1])) / 3)) << __DXT5_LUT_COLOR_SHIFT_B);
      // p3 = ((c0)+(2*c1))/3
      __DXT5_LUT_COLOR_VALUE_R[index | 3] = (uint)((uint)((byte)(((__DXT5_LUT_4x8[cc0]) + (__DXT5_LUT_4x8[cc1] * 2)) / 3)) << __DXT5_LUT_COLOR_SHIFT_R);
      __DXT5_LUT_COLOR_VALUE_B[index | 3] = (uint)((uint)((byte)(((__DXT5_LUT_4x8[cc0]) + (__DXT5_LUT_4x8[cc1] * 2)) / 3)) << __DXT5_LUT_COLOR_SHIFT_B);
    }
  }
  for (int cc0 = 0; cc0 < 64; cc0++)
  {
    for (int cc1 = 0; cc1 < 64; cc1++)
    {
      int index = ((cc0 << 6) | cc1) << 2;
      __DXT5_LUT_COLOR_VALUE_G[index | 0] = (uint)(((uint)__DXT5_LUT_8x8[cc0]) << __DXT5_LUT_COLOR_SHIFT_G);
      __DXT5_LUT_COLOR_VALUE_G[index | 1] = (uint)(((uint)__DXT5_LUT_8x8[cc1]) << __DXT5_LUT_COLOR_SHIFT_G);
      // Each RGB image data block is encoded according to the BC1 formats,
      // with the exception that the two code bits always use the non-transparent encodings.
      // In other words, they are treated as though color0 > color1,
      // regardless of the actual values of color0 and color1.
      // p2 = ((2*c0)+(c1))/3
      __DXT5_LUT_COLOR_VALUE_G[index | 2] = (uint)((uint)((byte)(((__DXT5_LUT_8x8[cc0] * 2) + (__DXT5_LUT_8x8[cc1])) / 3)) << __DXT5_LUT_COLOR_SHIFT_G);
      // p3 = ((c0)+(2*c1))/3
      __DXT5_LUT_COLOR_VALUE_G[index | 3] = (uint)((uint)((byte)(((__DXT5_LUT_8x8[cc0]) + (__DXT5_LUT_8x8[cc1] * 2)) / 3)) << __DXT5_LUT_COLOR_SHIFT_G);
    }
  }
}

#pragma endregion

#pragma region "### DXT1 set output pixel format (rebuild LUTs if necessary) ###"

void DXT5SetOutputPixelFormat(DXT5PixelFormat pixelFormat)
{
  bool rebuildLut = (__DXT5_LUT_OutPixelFormat != pixelFormat);
  __DXT5_LUT_OutPixelFormat = pixelFormat;
  switch (__DXT5_LUT_OutPixelFormat)
  {
  case DXT5PixelFormat_ABGR:
    __DXT5_LUT_COLOR_SHIFT_A = 0;
    __DXT5_LUT_COLOR_SHIFT_B = 8;
    __DXT5_LUT_COLOR_SHIFT_G = 16;
    __DXT5_LUT_COLOR_SHIFT_R = 24;
    break;
  case DXT5PixelFormat_ARGB:
    __DXT5_LUT_COLOR_SHIFT_A = 0;
    __DXT5_LUT_COLOR_SHIFT_R = 8;
    __DXT5_LUT_COLOR_SHIFT_G = 16;
    __DXT5_LUT_COLOR_SHIFT_B = 24;
    break;
  case DXT5PixelFormat_RGBA:
    __DXT5_LUT_COLOR_SHIFT_R = 0;
    __DXT5_LUT_COLOR_SHIFT_G = 8;
    __DXT5_LUT_COLOR_SHIFT_B = 16;
    __DXT5_LUT_COLOR_SHIFT_A = 24;
    break;
  case DXT5PixelFormat_BGRA:
  default:
    __DXT5_LUT_COLOR_SHIFT_B = 0;
    __DXT5_LUT_COLOR_SHIFT_G = 8;
    __DXT5_LUT_COLOR_SHIFT_R = 16;
    __DXT5_LUT_COLOR_SHIFT_A = 24;
    break;
  }
  if (rebuildLut || null == __DXT5_LUT_COLOR_VALUE_R)
  {
    __DXT5_LUT_COLOR_VALUE_A_Build();
    __DXT5_LUT_COLOR_VALUE_RGB_Build();
  }
}

#pragma endregion

#pragma region "### DXT5 decompress exported function ###"

/// <summary>
/// Decompresses all the blocks of a DXT1 (BC1) compressed texture and stores the resulting pixels in 'image'.
/// </summary>
/// <param name="width">Texture width.</param>
/// <param name="height">Texture height.</param>
/// <param name="p_input">pointer to compressed DXT1 blocks.</param>
/// <param name="p_output">pointer to the image where the decoded pixels will be stored.</param>
void DXT5Decompress(uint width, uint height, byte* p_input, byte* p_output)
{
  if (NULL == __DXT5_LUT_COLOR_VALUE_A)
  {
    __DXT5_LUT_COLOR_VALUE_A_Build();
    __DXT5_LUT_COLOR_VALUE_RGB_Build();
  }

  // direct copy paste from c# code, not even comments changed

  byte* source = (byte*)p_input;
  uint* target = (uint*)p_output;
  uint target_4scans = (width << 2);
  uint x_block_count = (width + 3) >> 2;
  uint y_block_count = (height + 3) >> 2;

  //############################################################
  if ((x_block_count << 2) != width || (y_block_count << 2) != height)
  {
    // for images that do not fit in 4x4 texel bounds

    uint* EOI = target + (width * height);
    // target : advance by 4 scan lines
    for (uint y_block = 0; y_block < y_block_count; y_block++, target += target_4scans)
    {
      uint* texel_x = target;
      // texel: advance by 4 texels
      for (uint x_block = 0; x_block < x_block_count; x_block++, source += 16, texel_x += 4)
      {
        // read DXT5 (BC3) block data
        //byte ac0 = *(byte*)(source);            // 00    : a0       (8bit)
        //byte ac1 = *(byte*)(source+ 1);         // 01    : a1       (8bit)
        ulong acfnlut = *(ulong*)(source + 2);  // 02-07 : afn LUT  (48bits) 4x4x3bits
        ushort cc0 = *(ushort*)(source + 8);    // 08-09 : cc0      (16bits)
        ushort cc1 = *(ushort*)(source + 10);   // 0a-0b : cc1      (16bits)
        uint ccfnlut = *(uint*)(source + 12);   // 0c-0f : ccfn LUT (32bits) 4x4x2bits

        // alpha code and color code [r,g,b] indexes to lut values
        uint ccr = ((uint)((cc0 & 0xf800) >> 4) | (uint)((cc1 & 0xf800) >> 9));
        uint ccg = ((uint)((cc0 & 0x07E0) << 3) | (uint)((cc1 & 0x07E0) >> 3));
        uint ccb = ((uint)((cc0 & 0x001F) << 7) | (uint)((cc1 & 0x001F) << 2));
        //uint ac = ((uint)ac0 << 3) | ((uint)ac1 << 11);
        uint ac = (uint)((*(ushort*)source) << 3);

        // process 4x4 texels
        uint* texel = texel_x;
        for (uint by = 0; by < 4; by++, texel += width)
        {
          //############################################################
          // Check Y Bound (break: no more texels available for block)
          if (texel >= EOI) break;
          //############################################################
          for (uint bx = 0; bx < 4; bx++, acfnlut >>= 3, ccfnlut >>= 2)
          {
            //############################################################
            // Check X Bound (continue: need ac|ccfnlut to complete shift)
            if (texel + bx >= EOI) continue;
            //############################################################
            uint acfn = (uint)(acfnlut & 0x07);
            uint ccfn = (uint)(ccfnlut & 0x03);

            *(texel + bx) = (uint)
              (
                __DXT5_LUT_COLOR_VALUE_A[ac | acfn] |
                __DXT5_LUT_COLOR_VALUE_R[ccr | ccfn] |
                __DXT5_LUT_COLOR_VALUE_G[ccg | ccfn] |
                __DXT5_LUT_COLOR_VALUE_B[ccb | ccfn]
              );
          }//bx
        }//by
      }//x_block
    }//y_block
    return;
  }
  //############################################################
  //ProcessWithoutCheckingTexelBounds:
  //
  // NOTICE: source and target ARE aligned as 4x4 texels
  //
  // target : advance by 4 scan lines
  for (uint y_block = 0; y_block < y_block_count; y_block++, target+=target_4scans)
  {
    // texel: advance by 4 texels
    uint* texel_x = target;
    for (uint x_block = 0; x_block < x_block_count; x_block++, source+=16, texel_x+=4)
    {
      // read DXT5 (BC3) block data
      //byte ac0 = *(byte*)(source);            // 00    : a0       (8bit)
      //byte ac1 = *(byte*)(source + 1);        // 01    : a1       (8bit)
      ulong acfnlut = *(ulong*)(source + 2);  // 02-07 : afn LUT  (48bits) 4x4x3bits
      ushort cc0 = *(ushort*)(source + 8);    // 08-09 : cc0      (16bits)
      ushort cc1 = *(ushort*)(source + 10);   // 0a-0b : cc1      (16bits)
      uint ccfnlut = *(uint*)(source + 12);   // 0c-0f : ccfn LUT (32bits) 4x4x2bits

      // alpha code and color code [r,g,b] indexes to luts
      uint ccr = ((uint)((cc0 & 0xf800) >> 4) | (uint)((cc1 & 0xf800) >> 9));
      uint ccg = ((uint)((cc0 & 0x07E0) << 3) | (uint)((cc1 & 0x07E0) >> 3));
      uint ccb = ((uint)((cc0 & 0x001F) << 7) | (uint)((cc1 & 0x001F) << 2));
      //uint ac = ((uint)ac0 << 3) | ((uint)ac1 << 11);
      uint ac = (uint)((*(ushort*)source) << 3);

      // process 4x4 color code
      uint* texel = texel_x;
      for (uint by = 0; by < 4; by++, texel += width)
      {
        for (uint bx = 0; bx < 4; bx++, acfnlut>>=3, ccfnlut>>=2)
        {
          uint acfn = (uint)(acfnlut & 0x07);
          uint ccfn = (uint)(ccfnlut & 0x03);

          *(texel + bx) = (uint)
            (
              __DXT5_LUT_COLOR_VALUE_A[ac | acfn] |
              __DXT5_LUT_COLOR_VALUE_R[ccr | ccfn] |
              __DXT5_LUT_COLOR_VALUE_G[ccg | ccfn] |
              __DXT5_LUT_COLOR_VALUE_B[ccb | ccfn]
            );
        }//bx
      }//by
    }//x_block
  }//y_block
	return;
  //
  //############################################################
  // NOTICE: source and target ARE NOT aligned to 4x4 texels,
  //         We must check for End Of Image (EOI) in this case.
  //############################################################
  // lazy to write boundary separate processings.
  // Just end of image (EOI) pointer check only.
  // considering that I have encountered few images that are not
  // aligned to 4x4 texels, this should be almost never called.
  // takes ~500us (0.5ms) more time processing 2MB pixel images.
  //############################################################
  //

}


""".}