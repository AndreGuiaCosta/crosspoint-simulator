#pragma once

#include "esp_err.h"

struct esp_transport_handle_t;

// Used as a function pointer in esp_http_client_config_t. Returning ESP_FAIL
// would bail before TLS even starts — but on host we never reach the HTTP
// path through OtaUpdater (network layer is stubbed via NetworkClientSecure
// elsewhere), so this is just a linkable address.
inline esp_err_t esp_crt_bundle_attach(void*) { return ESP_FAIL; }
