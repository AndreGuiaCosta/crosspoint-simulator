#pragma once

#include <cstddef>
#include <cstdint>

// Standard CRC-32/ISO-HDLC (poly 0xEDB88320, reflected) — same algorithm
// the on-device esp_rom_crc32_le uses. Computing it correctly here means
// OtaBootSwitch's CRC writes match what the bootloader expects, even
// though the surrounding flash code is stubbed.
inline uint32_t esp_rom_crc32_le(uint32_t crc, const uint8_t* buf, uint32_t len) {
  crc = ~crc;
  for (uint32_t i = 0; i < len; ++i) {
    crc ^= buf[i];
    for (int j = 0; j < 8; ++j) {
      crc = (crc >> 1) ^ (0xEDB88320u & -(crc & 1));
    }
  }
  return ~crc;
}
