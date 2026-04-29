#include "JPEGDEC.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <csetjmp>

extern "C" {
#include <jpeglib.h>
}

namespace {

// libjpeg's default error_exit calls exit() — replace with longjmp so a bad
// JPEG fails cleanly instead of taking down the simulator.
struct CrosspointJpegError {
  struct jpeg_error_mgr pub;
  jmp_buf jmp;
};

void crosspointJpegErrorExit(j_common_ptr cinfo) {
  auto* err = reinterpret_cast<CrosspointJpegError*>(cinfo->err);
  longjmp(err->jmp, 1);
}

void crosspointJpegOutputMessage(j_common_ptr) {}

constexpr int BLOCK = 16;

}  // namespace

int JPEGDEC::open(const char* filename, JPEG_OPEN_CALLBACK openCb, JPEG_CLOSE_CALLBACK closeCb,
                  JPEG_READ_CALLBACK readCb, JPEG_SEEK_CALLBACK seekCb, JPEG_DRAW_CALLBACK drawCb) {
  bytes_.clear();
  width_ = height_ = 0;
  lastError_ = 0;
  drawCb_ = drawCb;

  if (!openCb || !readCb || !seekCb) {
    lastError_ = -1;
    return 0;
  }

  int32_t size = 0;
  void* handle = openCb(filename ? filename : "", &size);
  if (!handle || size <= 0) {
    if (handle && closeCb) closeCb(handle);
    lastError_ = -1;
    return 0;
  }

  bytes_.resize(static_cast<size_t>(size));
  JPEGFILE jf{handle, 0, size};
  if (seekCb(&jf, 0) < 0) {
    if (closeCb) closeCb(handle);
    bytes_.clear();
    lastError_ = -1;
    return 0;
  }
  int32_t got = 0;
  while (got < size) {
    int32_t n = readCb(&jf, bytes_.data() + got, size - got);
    if (n <= 0) break;
    got += n;
  }
  if (closeCb) closeCb(handle);
  if (got != size) {
    bytes_.clear();
    lastError_ = -1;
    return 0;
  }

  jpeg_decompress_struct cinfo;
  CrosspointJpegError jerr;
  std::memset(&cinfo, 0, sizeof(cinfo));
  cinfo.err = jpeg_std_error(&jerr.pub);
  jerr.pub.error_exit = crosspointJpegErrorExit;
  jerr.pub.output_message = crosspointJpegOutputMessage;

  if (setjmp(jerr.jmp)) {
    jpeg_destroy_decompress(&cinfo);
    bytes_.clear();
    lastError_ = -1;
    return 0;
  }

  jpeg_create_decompress(&cinfo);
  jpeg_mem_src(&cinfo, bytes_.data(), bytes_.size());
  if (jpeg_read_header(&cinfo, TRUE) != JPEG_HEADER_OK) {
    jpeg_destroy_decompress(&cinfo);
    bytes_.clear();
    lastError_ = -1;
    return 0;
  }
  width_ = static_cast<int>(cinfo.image_width);
  height_ = static_cast<int>(cinfo.image_height);
  jpeg_destroy_decompress(&cinfo);

  // Cap so a malformed/huge JPEG can't OOM the host.
  constexpr int MAX_DIM = 8192;
  if (width_ <= 0 || height_ <= 0 || width_ > MAX_DIM || height_ > MAX_DIM) {
    bytes_.clear();
    lastError_ = -1;
    return 0;
  }
  return 1;
}

void JPEGDEC::close() {
  bytes_.clear();
  bytes_.shrink_to_fit();
  width_ = height_ = 0;
  drawCb_ = nullptr;
  userPtr_ = nullptr;
}

int JPEGDEC::decode(int /*x*/, int /*y*/, int /*options*/) {
  if (bytes_.empty() || !drawCb_ || width_ <= 0 || height_ <= 0) {
    lastError_ = -1;
    return 0;
  }

  jpeg_decompress_struct cinfo;
  CrosspointJpegError jerr;
  std::memset(&cinfo, 0, sizeof(cinfo));
  cinfo.err = jpeg_std_error(&jerr.pub);
  jerr.pub.error_exit = crosspointJpegErrorExit;
  jerr.pub.output_message = crosspointJpegOutputMessage;

  // Declared outside the setjmp scope so the longjmp path frees it cleanly.
  std::vector<uint8_t> image;

  if (setjmp(jerr.jmp)) {
    jpeg_destroy_decompress(&cinfo);
    lastError_ = -1;
    return 0;
  }

  jpeg_create_decompress(&cinfo);
  jpeg_mem_src(&cinfo, bytes_.data(), bytes_.size());
  if (jpeg_read_header(&cinfo, TRUE) != JPEG_HEADER_OK) {
    jpeg_destroy_decompress(&cinfo);
    lastError_ = -1;
    return 0;
  }
  cinfo.out_color_space = JCS_GRAYSCALE;
  jpeg_start_decompress(&cinfo);

  const int outW = static_cast<int>(cinfo.output_width);
  const int outH = static_cast<int>(cinfo.output_height);
  image.assign(static_cast<size_t>(outW) * static_cast<size_t>(outH), 0);

  while (cinfo.output_scanline < cinfo.output_height) {
    JSAMPROW row = image.data() + static_cast<size_t>(cinfo.output_scanline) * outW;
    if (jpeg_read_scanlines(&cinfo, &row, 1) != 1) {
      jpeg_destroy_decompress(&cinfo);
      lastError_ = -1;
      return 0;
    }
  }
  jpeg_finish_decompress(&cinfo);
  jpeg_destroy_decompress(&cinfo);

  // JpegToBmpConverter assumes left-to-right, top-to-bottom MCU order.
  uint8_t blockBuf[BLOCK * BLOCK];
  for (int by = 0; by < outH; by += BLOCK) {
    const int blockH = std::min(BLOCK, outH - by);
    for (int bx = 0; bx < outW; bx += BLOCK) {
      const int blockW = std::min(BLOCK, outW - bx);
      std::memset(blockBuf, 0, sizeof(blockBuf));
      for (int r = 0; r < blockH; r++) {
        std::memcpy(blockBuf + r * BLOCK, image.data() + static_cast<size_t>(by + r) * outW + bx,
                    static_cast<size_t>(blockW));
      }
      JPEGDRAW draw{};
      draw.pUser = userPtr_;
      draw.pPixels = blockBuf;
      draw.x = bx;
      draw.y = by;
      draw.iWidth = BLOCK;
      draw.iHeight = blockH;
      draw.iWidthUsed = blockW;
      if (drawCb_(&draw) == 0) {
        lastError_ = -2;
        return 0;
      }
    }
  }

  return 1;
}
