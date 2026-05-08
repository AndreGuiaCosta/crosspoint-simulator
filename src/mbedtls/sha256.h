#pragma once

#include <openssl/sha.h>

#include <cstddef>
#include <cstdint>
#include <cstring>

// Stub mbedtls_sha256_* via OpenSSL on Linux/WSL (libssl already linked
// for MD5Builder). Same digest as the on-device mbedtls implementation.
//
// OpenSSL 3.x deprecates the SHA256_* low-level API; the simulator's
// platformio overlay already passes -Wno-deprecated-declarations.

typedef struct {
  SHA256_CTX ctx;
} mbedtls_sha256_context;

inline void mbedtls_sha256_init(mbedtls_sha256_context* c) { std::memset(c, 0, sizeof(*c)); }
inline void mbedtls_sha256_free(mbedtls_sha256_context*) {}
inline int mbedtls_sha256_starts(mbedtls_sha256_context* c, int /*is224*/) {
  SHA256_Init(&c->ctx);
  return 0;
}
inline int mbedtls_sha256_update(mbedtls_sha256_context* c, const uint8_t* data, size_t len) {
  SHA256_Update(&c->ctx, data, len);
  return 0;
}
inline int mbedtls_sha256_finish(mbedtls_sha256_context* c, uint8_t out[32]) {
  SHA256_Final(out, &c->ctx);
  return 0;
}
