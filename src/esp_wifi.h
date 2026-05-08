#pragma once

#include "esp_err.h"

// Power-save modes used by the OTA path. Values mirror the on-device enum
// for documentation only; the stubbed setter is a no-op.
typedef enum {
  WIFI_PS_NONE = 0,
  WIFI_PS_MIN_MODEM = 1,
  WIFI_PS_MAX_MODEM = 2,
} wifi_ps_type_t;

inline esp_err_t esp_wifi_set_ps(wifi_ps_type_t) { return ESP_OK; }
