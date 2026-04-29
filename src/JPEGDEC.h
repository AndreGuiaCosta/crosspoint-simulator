#pragma once
// Simulator implementation of JPEGDEC (bitbank2/JPEGDEC) backed by
// libjpeg-turbo. The on-device library streams MCUs via a draw callback; we
// slurp the whole JPEG into RAM, decode to grayscale with libjpeg, then
// re-emit the result in 16x16 blocks so the firmware-side
// JpegToBmpConverter / JpegToFramebufferConverter (which were written
// against the streaming contract) work unmodified.
//
// Only EIGHT_BIT_GRAYSCALE is honored — that's the only pixel type any
// current caller sets. RGB565 is accepted at the API level but quietly
// downgraded to grayscale; if a future caller starts depending on it the
// callback will need a parallel emit path.
//
// Linker dep: -ljpeg (libjpeg-turbo on Debian/Ubuntu via libjpeg-turbo8-dev).

#include <cstddef>
#include <cstdint>
#include <vector>

// Scale options passed to decode() — accepted but the simulator path always
// decodes at native resolution and lets the caller scale, since libjpeg-turbo's
// scaling rules differ subtly from JPEGDEC's.
#define JPEG_SCALE_EIGHTH 4
#define JPEG_SCALE_QUARTER 2
#define JPEG_SCALE_HALF 1

// Pixel output types
#define EIGHT_BIT_GRAYSCALE 1
#define RGB565_LITTLE_ENDIAN 2

// JPEG stream types (we always report baseline)
#define JPEG_MODE_BASELINE 0
#define JPEG_MODE_PROGRESSIVE 1

struct JPEGFILE {
  void* fHandle;
  int32_t iPos;
  int32_t iSize;
};

struct JPEGDRAW {
  void* pUser;
  uint8_t* pPixels;
  int x;
  int y;
  int iWidth;
  int iHeight;
  int iWidthUsed;
};

using JPEG_DRAW_CALLBACK = int (*)(JPEGDRAW*);
using JPEG_OPEN_CALLBACK = void* (*)(const char*, int32_t*);
using JPEG_CLOSE_CALLBACK = void (*)(void*);
using JPEG_READ_CALLBACK = int32_t (*)(JPEGFILE*, uint8_t*, int32_t);
using JPEG_SEEK_CALLBACK = int32_t (*)(JPEGFILE*, int32_t);

class JPEGDEC {
 public:
  JPEGDEC() = default;
  ~JPEGDEC() = default;

  int open(const char* filename, JPEG_OPEN_CALLBACK openCb, JPEG_CLOSE_CALLBACK closeCb, JPEG_READ_CALLBACK readCb,
           JPEG_SEEK_CALLBACK seekCb, JPEG_DRAW_CALLBACK drawCb);
  void close();

  int getWidth() const { return width_; }
  int getHeight() const { return height_; }
  int getLastError() const { return lastError_; }
  int getJPEGType() const { return JPEG_MODE_BASELINE; }
  void setPixelType(int t) { pixelType_ = t; }
  void setUserPointer(void* u) { userPtr_ = u; }

  int decode(int x, int y, int options);

 private:
  // Whole-file buffer. Cover JPEGs are at most a few MB; on a host PC this
  // is fine and keeps libjpeg's source manager trivial (jpeg_mem_src).
  std::vector<uint8_t> bytes_;
  int width_ = 0;
  int height_ = 0;
  int lastError_ = 0;
  int pixelType_ = EIGHT_BIT_GRAYSCALE;
  void* userPtr_ = nullptr;
  JPEG_DRAW_CALLBACK drawCb_ = nullptr;
};
