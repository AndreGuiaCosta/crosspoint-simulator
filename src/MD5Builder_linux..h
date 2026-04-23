#pragma once

// Linux stub: replace src/MD5Builder.h with this file on Linux.
// Requires: sudo apt install libssl-dev  (Debian/Ubuntu)
//           sudo dnf install openssl-devel  (Fedora)
// Add to platformio.ini build_flags: -lssl -lcrypto
//
// OpenSSL 3.x deprecates MD5_Init/Update/Final; suppress with
// -Wno-deprecated-declarations in build_flags if needed.

#include <openssl/md5.h>

#include <cstdint>
#include <cstdio>
#include <cstring>

#include "WString.h"

class MD5Builder {
 public:
  MD5Builder() { memset(digest_, 0, sizeof(digest_)); }

  void begin() { MD5_Init(&ctx_); }

  void add(const uint8_t* data, size_t len) { MD5_Update(&ctx_, data, len); }

  void add(const char* str) {
    if (str) add(reinterpret_cast<const uint8_t*>(str), strlen(str));
  }

  void calculate() { MD5_Final(digest_, &ctx_); }

  String toString() const {
    char hex[33];
    for (int i = 0; i < 16; i++) {
      snprintf(hex + i * 2, 3, "%02x", digest_[i]);
    }
    return String(hex);
  }

 private:
  MD5_CTX ctx_{};
  uint8_t digest_[16];
};
