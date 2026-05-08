#pragma once
#include <cstdint>
#include <cstring>

#include "esp_err.h"

typedef enum {
  ESP_MAC_WIFI_STA = 0,
  ESP_MAC_WIFI_SOFTAP = 1,
  ESP_MAC_BT = 2,
  ESP_MAC_ETH = 3,
} esp_mac_type_t;

// Simulator stubs return a fixed fake MAC address.
static constexpr uint8_t kSimulatorFakeMac[6] = {0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01};

inline int esp_efuse_mac_get_default(uint8_t mac[6]) {
  std::memcpy(mac, kSimulatorFakeMac, 6);
  return 0;
}

inline esp_err_t esp_read_mac(uint8_t mac[6], esp_mac_type_t /*type*/) {
  std::memcpy(mac, kSimulatorFakeMac, 6);
  return ESP_OK;
}
