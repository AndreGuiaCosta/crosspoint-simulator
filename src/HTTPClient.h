#pragma once

#include <array>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <memory>
#include <string>

#include "Stream.h"
#include "WString.h"

class NetworkClient;

enum { HTTPC_STRICT_FOLLOW_REDIRECTS, HTTP_CODE_OK = 200 };

class HTTPClient {
 public:
  HTTPClient() {}
  ~HTTPClient() {}

  void begin(NetworkClient &client, const char *url) {
    (void)client;
    url_ = url ? url : "";
    responseBody_.s.clear();
    statusCode_ = 0;
  }
  void setFollowRedirects(int mode) {}
  void addHeader(const char *name, const String &value) {
    if (name)
      headers_[name] = value.c_str();
  }
  void addHeader(const char *name, const char *value) {
    if (name)
      headers_[name] = value ? value : "";
  }
  void setAuthorization(const char *user, const char *pass) {
    if (user && pass)
      basicAuth_ = std::string(user) + ":" + pass;
  }

  int GET() { return perform("GET", nullptr); }
  int POST() { return perform("POST", ""); }
  int POST(const char *body) { return perform("POST", body ? body : ""); }
  int PUT(const char *body) { return perform("PUT", body ? body : ""); }
  int PUT(const String &body) { return perform("PUT", body.c_str()); }

  String getString() { return responseBody_; }
  int getSize() { return static_cast<int>(responseBody_.length()); }
  int writeToStream(Stream *stream) {
    if (!stream)
      return 0;
    return static_cast<int>(
        stream->write(reinterpret_cast<const uint8_t *>(responseBody_.c_str()),
                      responseBody_.length()));
  }

  void end() {
    url_.clear();
    headers_.clear();
    basicAuth_.clear();
    responseBody_ = "";
    statusCode_ = 0;
  }

 private:
  std::string url_;
  std::map<std::string, std::string> headers_;
  std::string basicAuth_;
  String responseBody_;
  int statusCode_ = 0;

  static std::string shellQuote(const std::string &value) {
    std::string out = "'";
    for (char c : value) {
      if (c == '\'')
        out += "'\\''";
      else
        out += c;
    }
    out += "'";
    return out;
  }

  int perform(const char *method, const char *body) {
    if (url_.empty())
      return 0;

    std::string cmd =
        "curl -L -sS --connect-timeout 10 --max-time 60 -w '\\n%{http_code}'";
    if (method && std::string(method) != "GET")
      cmd += " -X " + shellQuote(method);
    for (const auto &header : headers_) {
      cmd += " -H " + shellQuote(header.first + ": " + header.second);
    }
    if (!basicAuth_.empty())
      cmd += " -u " + shellQuote(basicAuth_);
    if (body) {
      cmd += " --data-binary " + shellQuote(body);
    }
    cmd += " " + shellQuote(url_);

    FILE *pipe = popen(cmd.c_str(), "r");
    if (!pipe)
      return 0;

    std::string response;
    std::array<char, 4096> buffer{};
    while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe)) {
      response += buffer.data();
    }
    const int rc = pclose(pipe);
    if (rc != 0 && response.empty())
      return 0;

    const size_t nl = response.rfind('\n');
    if (nl == std::string::npos)
      return 0;
    responseBody_ = response.substr(0, nl);
    statusCode_ = std::atoi(response.substr(nl + 1).c_str());
    return statusCode_;
  }
};
