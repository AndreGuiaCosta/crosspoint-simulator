#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "WString.h"

class NetworkClient;
class Stream;

// Constants the firmware passes to HTTPClient. The numeric values are
// arbitrary in the simulator — only setFollowRedirects branches on the
// "off" sentinel below.
enum {
  HTTPC_DISABLE_FOLLOW_REDIRECTS = 0,
  HTTPC_STRICT_FOLLOW_REDIRECTS = 1,
  HTTPC_FORCE_FOLLOW_REDIRECTS = 2,
  HTTP_CODE_OK = 200,
};

/**
 * libcurl-backed Arduino-ESP32 HTTPClient stand-in for the simulator.
 *
 * Mirrors the subset of the real API the firmware uses (begin/addHeader/
 * GET/POST/PUT/getString/getSize/writeToStream/end). HTTP and HTTPS are
 * both routed through libcurl; the NetworkClient* passed to begin() is
 * inspected only to honour setInsecure() on the secure variant.
 *
 * Negative return codes from GET/POST/PUT mirror the firmware contract:
 * callers (e.g. ReadestAuthClient) test `code < 0` to detect transport
 * failures rather than HTTP error responses.
 */
class HTTPClient {
 public:
  HTTPClient() = default;
  ~HTTPClient() { end(); }

  void begin(NetworkClient& client, const char* url);
  void setFollowRedirects(int mode) { followRedirects = (mode != HTTPC_DISABLE_FOLLOW_REDIRECTS); }
  void addHeader(const char* name, const String& value) { addHeader(name, value.c_str()); }
  void addHeader(const char* name, const char* value);
  void setAuthorization(const char* user, const char* pass);
  void setConnectTimeout(int32_t timeoutMs) { connectTimeoutMs = timeoutMs; }
  void setTimeout(uint16_t timeoutMs) { readTimeoutMs = timeoutMs; }

  int GET();
  int POST();
  int POST(const char* body);
  int PUT(const char* body);
  int PUT(const String& body) { return PUT(body.c_str()); }

  String getString() const { return String(responseBody); }
  int getSize() const { return static_cast<int>(responseBody.size()); }
  // Replays the buffered response body to a Stream. Returns bytes written,
  // or a negative value if no response is available.
  int writeToStream(Stream* stream);

  void end();

 private:
  int perform(const char* method, const char* body, size_t bodyLen);

  std::string url;
  std::vector<std::string> headers;  // Stored as "Name: value" lines for curl_slist.
  std::string userPwd;               // Empty unless setAuthorization was called.
  std::string responseBody;
  bool insecure = false;
  bool followRedirects = false;
  int32_t connectTimeoutMs = 0;  // 0 = libcurl default.
  int32_t readTimeoutMs = 0;     // 0 = libcurl default.
};
