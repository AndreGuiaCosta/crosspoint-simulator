#pragma once
// libjpeg-turbo backend; emits MCUs in 16x16 blocks for the JPEGDEC contract.

#include <cstddef>
#include <cstdint>
#include <vector>

#define JPEG_SCALE_EIGHTH 4
#define JPEG_SCALE_QUARTER 2
#define JPEG_SCALE_HALF 1

#define EIGHT_BIT_GRAYSCALE 1
#define RGB565_LITTLE_ENDIAN 2

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
  std::vector<uint8_t> bytes_;
  int width_ = 0;
  int height_ = 0;
  int lastError_ = 0;
  int pixelType_ = EIGHT_BIT_GRAYSCALE;
  void* userPtr_ = nullptr;
  JPEG_DRAW_CALLBACK drawCb_ = nullptr;
};
