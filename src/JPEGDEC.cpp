#include "JPEGDEC.h"

#include <cstdio>
#include <cstring>
#include <csetjmp>

extern "C" {
#include <jpeglib.h>
}

namespace {

// libjpeg's default error handler calls exit() on a fatal error, which would
// take down the whole simulator. Replace error_exit with a longjmp so we can
// fail the open/decode cleanly.
struct CrosspointJpegError {
  struct jpeg_error_mgr pub;
  jmp_buf jmp;
};

void crosspointJpegErrorExit(j_common_ptr cinfo) {
  auto* err = reinterpret_cast<CrosspointJpegError*>(cinfo->err);
  // Suppress libjpeg's stderr spam in CI/sim runs — the firmware-side caller
  // already logs a friendly "JPEG decode failed" message.
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

  // Slurp the whole file via the supplied callbacks. The on-device library
  // streams from flash through these same hooks; on the host we trade a few
  // MB of RAM for a much simpler libjpeg wiring.
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

  // Read just the header to populate width/height. The full decompress pass
  // happens in decode(); we keep `bytes_` around so we can rerun libjpeg on
  // the same buffer without re-reading the file.
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

  if (width_ <= 0 || height_ <= 0) {
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

  // Decoded image (grayscale, full resolution). Allocated outside the
  // setjmp scope so the longjmp path can free it via the destructor.
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
  // Force libjpeg to do the colorspace conversion for us — covers stored as
  // colour JPEGs come out as a single grayscale plane that maps directly onto
  // the firmware's MCU buffer (which expects 8-bit grayscale).
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

  // Re-emit as 16x16 blocks (a JPEG MCU upper bound) so callers written
  // against the streaming JPEGDEC contract see the expected callback shape.
  // Stride is fixed at BLOCK; iWidthUsed/iHeight shrink at the right and
  // bottom edges. Order is left-to-right, top-to-bottom — JpegToBmpConverter
  // depends on that to flush MCU rows.
  uint8_t blockBuf[BLOCK * BLOCK];
  for (int by = 0; by < outH; by += BLOCK) {
    const int blockH = (outH - by) < BLOCK ? (outH - by) : BLOCK;
    for (int bx = 0; bx < outW; bx += BLOCK) {
      const int blockW = (outW - bx) < BLOCK ? (outW - bx) : BLOCK;
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
