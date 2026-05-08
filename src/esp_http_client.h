#pragma once

#include <cstddef>

#include "esp_err.h"

// Stub esp_http_client. The simulator never reaches the real OTA / kosync
// HTTP path (those flows are gated behind WiFi which is also a no-op on
// host); these definitions exist only so OtaUpdater.cpp /
// KOReaderSyncClient.cpp compile and link cleanly.

typedef void* esp_http_client_handle_t;

typedef enum {
  HTTP_METHOD_GET = 0,
  HTTP_METHOD_POST = 1,
  HTTP_METHOD_PUT = 2,
  HTTP_METHOD_DELETE = 3,
  HTTP_METHOD_HEAD = 4,
} esp_http_client_method_t;

typedef enum {
  HTTP_TRANSPORT_UNKNOWN = 0,
  HTTP_TRANSPORT_OVER_TCP,
  HTTP_TRANSPORT_OVER_SSL,
} esp_http_client_transport_t;

typedef enum {
  HTTP_EVENT_ERROR = 0,
  HTTP_EVENT_ON_CONNECTED,
  HTTP_EVENT_HEADERS_SENT,
  HTTP_EVENT_ON_HEADER,
  HTTP_EVENT_ON_DATA,
  HTTP_EVENT_ON_FINISH,
  HTTP_EVENT_DISCONNECTED,
} esp_http_client_event_id_t;

typedef struct esp_http_client_event {
  esp_http_client_event_id_t event_id;
  esp_http_client_handle_t client;
  void* data;
  int data_len;
  void* user_data;
  char* header_key;
  char* header_value;
} esp_http_client_event_t;

typedef esp_err_t (*http_event_handle_cb)(esp_http_client_event_t*);
typedef esp_err_t (*esp_http_client_crt_bundle_attach_cb)(void*);

typedef struct {
  const char* url;
  const char* host;
  int port;
  const char* username;
  const char* password;
  esp_http_client_method_t method;
  int timeout_ms;
  bool disable_auto_redirect;
  int max_redirection_count;
  int max_authorization_retries;
  http_event_handle_cb event_handler;
  esp_http_client_transport_t transport_type;
  int buffer_size;
  int buffer_size_tx;
  void* user_data;
  bool is_async;
  bool use_global_ca_store;
  bool skip_cert_common_name_check;
  esp_http_client_crt_bundle_attach_cb crt_bundle_attach;
  bool keep_alive_enable;
  int keep_alive_idle;
  int keep_alive_interval;
  int keep_alive_count;
} esp_http_client_config_t;

inline esp_http_client_handle_t esp_http_client_init(const esp_http_client_config_t*) { return nullptr; }
inline esp_err_t esp_http_client_perform(esp_http_client_handle_t) { return ESP_FAIL; }
inline esp_err_t esp_http_client_cleanup(esp_http_client_handle_t) { return ESP_OK; }
inline esp_err_t esp_http_client_set_header(esp_http_client_handle_t, const char*, const char*) { return ESP_FAIL; }
inline esp_err_t esp_http_client_set_post_field(esp_http_client_handle_t, const char*, int) { return ESP_FAIL; }
inline int esp_http_client_get_status_code(esp_http_client_handle_t) { return 0; }
inline bool esp_http_client_is_chunked_response(esp_http_client_handle_t) { return false; }
inline int esp_http_client_get_content_length(esp_http_client_handle_t) { return 0; }
