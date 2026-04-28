#pragma once

// Simulator implementation of Arduino-ESP32's MD5Builder, dispatching to
// CommonCrypto on macOS and OpenSSL on Linux/WSL. Both backends produce
// the same 32-char lowercase hex digest as the on-device implementation.
//
// Linux/WSL prerequisites:
//   sudo apt install libssl-dev      (Debian/Ubuntu)
//   sudo dnf install openssl-devel   (Fedora/RHEL)
// platformio.ini build_flags must link OpenSSL: -lssl -lcrypto
//
// OpenSSL 3.x deprecates MD5_Init/Update/Final; the simulator's
// platformio overlay already passes -Wno-deprecated-declarations so the
// deprecation warning is silenced.

#if defined(__APPLE__)
#include <CommonCrypto/CommonDigest.h>
#define MD5BUILDER_BACKEND_COMMONCRYPTO 1
#else
#include <openssl/md5.h>
#define MD5BUILDER_BACKEND_OPENSSL 1
#endif

#include <cstdint>
#include <cstdio>
#include <cstring>

#include "WString.h"

class MD5Builder {
 public:
  MD5Builder() { memset(digest_, 0, sizeof(digest_)); }

  void begin() {
#if defined(MD5BUILDER_BACKEND_COMMONCRYPTO)
    CC_MD5_Init(&ctx_);
#else
    MD5_Init(&ctx_);
#endif
  }

  void add(const uint8_t* data, size_t len) {
#if defined(MD5BUILDER_BACKEND_COMMONCRYPTO)
    CC_MD5_Update(&ctx_, data, static_cast<CC_LONG>(len));
#else
    MD5_Update(&ctx_, data, len);
#endif
  }

  void add(const char* str) {
    if (str) add(reinterpret_cast<const uint8_t*>(str), strlen(str));
  }

  void calculate() {
#if defined(MD5BUILDER_BACKEND_COMMONCRYPTO)
    CC_MD5_Final(digest_, &ctx_);
#else
    MD5_Final(digest_, &ctx_);
#endif
  }

  String toString() const {
    char hex[33];
    for (int i = 0; i < 16; i++) {
      snprintf(hex + i * 2, 3, "%02x", digest_[i]);
    }
    return String(hex);
  }

 private:
#if defined(MD5BUILDER_BACKEND_COMMONCRYPTO)
  CC_MD5_CTX ctx_{};
#else
  MD5_CTX ctx_{};
#endif
  uint8_t digest_[16];
};
