#include "HTTPClient.h"

#include <curl/curl.h>

#include <cstdio>
#include <cstring>
#include <mutex>

#include "NetworkClient.h"
#include "Stream.h"

namespace {
// Negative return codes that match the spirit of Arduino-ESP32's
// HTTPClient::ERROR_* enum: callers only check `< 0`, so the exact value
// matters less than the sign. We split connect vs. read for log clarity.
constexpr int HTTPC_ERROR_CONNECTION_REFUSED = -1;
constexpr int HTTPC_ERROR_SEND_HEADER_FAILED = -2;
constexpr int HTTPC_ERROR_READ_TIMEOUT = -11;
constexpr int HTTPC_ERROR_NO_HTTP_SERVER = -7;

void ensureCurlGlobalInit() {
  static std::once_flag flag;
  std::call_once(flag, []() { curl_global_init(CURL_GLOBAL_DEFAULT); });
}

size_t writeToString(void* contents, size_t size, size_t nmemb, void* userp) {
  const size_t total = size * nmemb;
  static_cast<std::string*>(userp)->append(static_cast<const char*>(contents), total);
  return total;
}

int mapCurlError(CURLcode rc) {
  switch (rc) {
    case CURLE_OK:
      return 0;
    case CURLE_COULDNT_CONNECT:
    case CURLE_COULDNT_RESOLVE_HOST:
    case CURLE_COULDNT_RESOLVE_PROXY:
      return HTTPC_ERROR_CONNECTION_REFUSED;
    case CURLE_OPERATION_TIMEDOUT:
      return HTTPC_ERROR_READ_TIMEOUT;
    case CURLE_SEND_ERROR:
      return HTTPC_ERROR_SEND_HEADER_FAILED;
    default:
      return HTTPC_ERROR_NO_HTTP_SERVER;
  }
}
}  // namespace

void HTTPClient::begin(NetworkClient& client, const char* url) {
  end();
  this->url = url ? url : "";
  // Only NetworkClientSecure has the insecure flag. dynamic_cast lets us
  // honour setInsecure() without forcing the firmware to call a setter on
  // HTTPClient itself (matches Arduino-ESP32's behaviour where the secure
  // client carries the trust config).
  if (auto* secure = dynamic_cast<NetworkClientSecure*>(&client)) {
    insecure = secure->isInsecure();
  } else {
    insecure = false;
  }
}

void HTTPClient::addHeader(const char* name, const char* value) {
  if (!name || !*name) return;
  std::string line = name;
  line += ": ";
  if (value) line += value;
  headers.push_back(std::move(line));
}

void HTTPClient::setAuthorization(const char* user, const char* pass) {
  userPwd.clear();
  if (user) userPwd = user;
  userPwd += ":";
  if (pass) userPwd += pass;
}

int HTTPClient::GET() { return perform("GET", nullptr, 0); }
int HTTPClient::POST() { return perform("POST", "", 0); }
int HTTPClient::POST(const char* body) { return perform("POST", body, body ? std::strlen(body) : 0); }
int HTTPClient::PUT(const char* body) { return perform("PUT", body, body ? std::strlen(body) : 0); }

int HTTPClient::writeToStream(Stream* stream) {
  if (!stream) return -1;
  // Mirror Arduino-ESP32's contract: returns total bytes written. The body
  // was buffered during perform(), so this is just a replay.
  const size_t n = responseBody.size();
  if (n == 0) return 0;
  stream->write(reinterpret_cast<const uint8_t*>(responseBody.data()), n);
  return static_cast<int>(n);
}

void HTTPClient::end() {
  url.clear();
  headers.clear();
  userPwd.clear();
  responseBody.clear();
  insecure = false;
  followRedirects = false;
  connectTimeoutMs = 0;
  readTimeoutMs = 0;
}

int HTTPClient::perform(const char* method, const char* body, size_t bodyLen) {
  if (url.empty()) return HTTPC_ERROR_CONNECTION_REFUSED;
  ensureCurlGlobalInit();

  CURL* easy = curl_easy_init();
  if (!easy) return HTTPC_ERROR_CONNECTION_REFUSED;

  responseBody.clear();
  curl_easy_setopt(easy, CURLOPT_URL, url.c_str());
  curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, followRedirects ? 1L : 0L);
  curl_easy_setopt(easy, CURLOPT_SSL_VERIFYPEER, insecure ? 0L : 1L);
  curl_easy_setopt(easy, CURLOPT_SSL_VERIFYHOST, insecure ? 0L : 2L);
  curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, writeToString);
  curl_easy_setopt(easy, CURLOPT_WRITEDATA, &responseBody);
  if (connectTimeoutMs > 0) curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT_MS, static_cast<long>(connectTimeoutMs));
  if (readTimeoutMs > 0) curl_easy_setopt(easy, CURLOPT_TIMEOUT_MS, static_cast<long>(readTimeoutMs));
  if (!userPwd.empty()) curl_easy_setopt(easy, CURLOPT_USERPWD, userPwd.c_str());

  // Method-specific options. POSTFIELDSIZE_LARGE lets a body contain NUL
  // bytes (curl would otherwise strlen it); harmless for JSON but the
  // right default. PUT goes via CUSTOMREQUEST + a fixed-length read of
  // POSTFIELDS — simplest path that doesn't require CURLOPT_READFUNCTION.
  if (std::strcmp(method, "POST") == 0) {
    curl_easy_setopt(easy, CURLOPT_POST, 1L);
    curl_easy_setopt(easy, CURLOPT_POSTFIELDS, body ? body : "");
    curl_easy_setopt(easy, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(bodyLen));
  } else if (std::strcmp(method, "PUT") == 0) {
    curl_easy_setopt(easy, CURLOPT_CUSTOMREQUEST, "PUT");
    curl_easy_setopt(easy, CURLOPT_POSTFIELDS, body ? body : "");
    curl_easy_setopt(easy, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(bodyLen));
  } else {
    curl_easy_setopt(easy, CURLOPT_HTTPGET, 1L);
  }

  curl_slist* slist = nullptr;
  for (const auto& h : headers) {
    slist = curl_slist_append(slist, h.c_str());
  }
  if (slist) curl_easy_setopt(easy, CURLOPT_HTTPHEADER, slist);

  const CURLcode rc = curl_easy_perform(easy);
  long httpCode = 0;
  if (rc == CURLE_OK) {
    curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &httpCode);
  } else {
    fprintf(stderr, "[HTTP] curl_easy_perform: %s (%d) url=%s\n", curl_easy_strerror(rc), rc, url.c_str());
  }

  if (slist) curl_slist_free_all(slist);
  curl_easy_cleanup(easy);

  return rc == CURLE_OK ? static_cast<int>(httpCode) : mapCurlError(rc);
}
