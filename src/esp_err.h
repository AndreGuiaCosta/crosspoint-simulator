#pragma once

// stdint included so this header is safely usable from C translation units
// (skip_efuse_blk_check.c) where it'd otherwise pull uint32_t from nowhere.
#include <stdint.h>

// esp_err_t is `int` on real ESP-IDF; mirror that here. ESP_OK == 0, anything
// else is an error. The stubs in this directory return ESP_FAIL (-1) so the
// OTA / firmware-flash code paths fail cleanly on host.

typedef int esp_err_t;

#ifndef ESP_OK
#define ESP_OK 0
#endif

#ifndef ESP_FAIL
#define ESP_FAIL -1
#endif

#define ESP_ERR_NO_MEM -2
#define ESP_ERR_INVALID_ARG -3
#define ESP_ERR_INVALID_STATE -4
#define ESP_ERR_NOT_FOUND -5
#define ESP_ERR_TIMEOUT -6
#define ESP_ERR_NOT_SUPPORTED -7

inline const char* esp_err_to_name(esp_err_t err) {
  return err == ESP_OK ? "ESP_OK" : "ESP_FAIL (simulator stub)";
}
