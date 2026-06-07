#pragma once
#include <cstdio>
#include <iostream>

#include "Arduino.h"
#include "Print.h"
#include "Stream.h"
#include "WString.h"

// Forward-decl rather than #include: HardwareSerial.h is pulled in everywhere,
// and ScriptDriver headers must not leak in. The ScriptDriver consumes this tee
// to feed its `expect` ring buffer (script-driver test harness).
namespace ScriptDriver {
void onLogChar(char c);
}

class HWCDC : public Stream {
public:
  void begin(unsigned long baud) {}
  void setTxTimeoutMs(uint32_t timeoutMs) {}
  size_t write(uint8_t c) override {
    std::cerr << (char)c;
    ScriptDriver::onLogChar((char)c);
    return 1;
  }
  size_t write(const uint8_t *buffer, size_t size) override {
    std::cerr.write((const char *)buffer, size);
    for (size_t i = 0; i < size; i++) ScriptDriver::onLogChar((char)buffer[i]);
    return size;
  }
  int available() override { return 0; }
  int read() override { return -1; }
  int peek() override { return -1; }
  template <typename... Args> void printf(const char *format, Args... args) {
    if constexpr (sizeof...(Args) == 0) {
      std::cerr << format;
      for (const char *p = format; *p; ++p) ScriptDriver::onLogChar(*p);
    } else {
      char buf[256];
      snprintf(buf, sizeof(buf), format, args...);
      std::cerr << buf;
      for (const char *p = buf; *p; ++p) ScriptDriver::onLogChar(*p);
    }
  }
  operator bool() const { return true; }
};

extern HWCDC Serial;
