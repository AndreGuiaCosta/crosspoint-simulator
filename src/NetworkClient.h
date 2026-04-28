#pragma once

#include <cstddef>
#include <cstdint>

#include "WString.h"

class Stream;

class NetworkClient {
 public:
  NetworkClient() {}
  virtual ~NetworkClient() {}
  virtual int connect(const char* host, uint16_t port) { return 1; }
  virtual size_t write(const uint8_t* buf, size_t size) { return size; }
  virtual size_t write(const char* str) { return write((const uint8_t*)str, strlen(str)); }
  virtual size_t write(uint8_t c) { return write(&c, 1); }
  virtual size_t write(Stream& stream) { return 0; }  // Dummy implementation
  virtual int available() { return 0; }
  virtual int read() { return -1; }
  virtual void stop() {}
  virtual uint8_t connected() { return 1; }
  // Drops any data buffered for this client. Real ESP32 NetworkClient added
  // this in newer Arduino-ESP32 releases; CrossPoint's web server relies on
  // it after a chunked download to discard residual bytes.
  virtual void clear() {}
  operator bool() { return true; }
};

class NetworkClientSecure : public NetworkClient {
 public:
  // Real Arduino-ESP32 disables certificate verification when this is called.
  // The simulator's libcurl-backed HTTPClient reads the flag at request time
  // and forwards it to CURLOPT_SSL_VERIFY{PEER,HOST}.
  void setInsecure() { insecure = true; }
  bool isInsecure() const { return insecure; }

  // CrossPoint's auth client calls this on the firmware to install the
  // bundled CA trust store. The simulator relies on the system CA bundle
  // (libcurl picks it up automatically), so we accept the call as a no-op.
  void setCACertBundle(const uint8_t* /*bundle*/) {}

 private:
  bool insecure = false;
};