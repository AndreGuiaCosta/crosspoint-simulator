#pragma once

#include "esp_err.h"
#include "esp_http_client.h"

// In-progress sentinel for the perform-loop. Real ESP-IDF defines this in
// esp_https_ota.h; any non-zero value distinct from ESP_OK works for stubs
// since esp_https_ota_begin() already fails and the loop never runs.
#define ESP_ERR_HTTPS_OTA_IN_PROGRESS -0x9001

typedef void* esp_https_ota_handle_t;

typedef esp_err_t (*esp_https_ota_http_client_init_cb_t)(esp_http_client_handle_t);

typedef struct {
  const esp_http_client_config_t* http_config;
  esp_https_ota_http_client_init_cb_t http_client_init_cb;
  bool partial_http_download;
  int max_http_request_size;
} esp_https_ota_config_t;

// All operations fail; OTA over HTTPS isn't meaningful on host.
inline esp_err_t esp_https_ota_begin(const esp_https_ota_config_t*, esp_https_ota_handle_t* out) {
  if (out) *out = nullptr;
  return ESP_FAIL;
}
inline esp_err_t esp_https_ota_perform(esp_https_ota_handle_t) { return ESP_FAIL; }
inline esp_err_t esp_https_ota_finish(esp_https_ota_handle_t) { return ESP_FAIL; }
inline int esp_https_ota_get_image_len_read(esp_https_ota_handle_t) { return 0; }
inline bool esp_https_ota_is_complete_data_received(esp_https_ota_handle_t) { return false; }
