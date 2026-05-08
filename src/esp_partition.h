#pragma once

#include <cstddef>
#include <cstdint>

#include "esp_err.h"

// Minimal esp_partition stubs so FirmwareFlasher.cpp / OtaBootSwitch.cpp
// compile and link on host. All operations return ESP_FAIL — the SD-card
// firmware flash flow can't actually mutate flash on the desktop.

typedef enum {
  ESP_PARTITION_TYPE_APP = 0x00,
  ESP_PARTITION_TYPE_DATA = 0x01,
} esp_partition_type_t;

typedef enum {
  ESP_PARTITION_SUBTYPE_APP_FACTORY = 0x00,
  ESP_PARTITION_SUBTYPE_APP_OTA_0 = 0x10,
  ESP_PARTITION_SUBTYPE_APP_OTA_1 = 0x11,
  ESP_PARTITION_SUBTYPE_DATA_OTA = 0x00,
  ESP_PARTITION_SUBTYPE_ANY = 0xFF,
} esp_partition_subtype_t;

typedef struct {
  esp_partition_type_t type;
  esp_partition_subtype_t subtype;
  uint32_t address;
  uint32_t size;
  uint32_t erase_size;
  char label[17];
  bool encrypted;
  bool readonly;
} esp_partition_t;

typedef void* esp_partition_iterator_t;

inline const esp_partition_t* esp_partition_find_first(esp_partition_type_t, esp_partition_subtype_t, const char*) {
  return nullptr;
}

inline esp_err_t esp_partition_erase_range(const esp_partition_t*, size_t, size_t) { return ESP_FAIL; }
inline esp_err_t esp_partition_write(const esp_partition_t*, size_t, const void*, size_t) { return ESP_FAIL; }
inline esp_err_t esp_partition_read(const esp_partition_t*, size_t, void*, size_t) { return ESP_FAIL; }
