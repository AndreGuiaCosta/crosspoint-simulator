#pragma once
#include <algorithm>
#include <cstdio>
#include <iostream>

#include "Arduino.h"
#include "Print.h"
#include "ScriptDriver.h"
#include "Stream.h"
#include "WString.h"
class HWCDC : public Stream {
 public:
  void begin(unsigned long baud) {}
  size_t write(uint8_t c) override {
    std::cerr << (char)c;
    ScriptDriver::onLogChar(static_cast<char>(c));
    return 1;
  }
  size_t write(const uint8_t* buffer, size_t size) override {
    std::cerr.write((const char*)buffer, size);
    for (size_t i = 0; i < size; ++i) ScriptDriver::onLogChar(static_cast<char>(buffer[i]));
    return size;
  }
  int available() override { return 0; }
  int read() override { return -1; }
  int peek() override { return -1; }
  template <typename... Args>
  void printf(const char* format, Args... args) {
    char buf[256];
    int n = snprintf(buf, sizeof(buf), format, args...);
    std::cerr << buf;
    if (n > 0) {
      const size_t toFeed = std::min(static_cast<size_t>(n), sizeof(buf) - 1);
      for (size_t i = 0; i < toFeed; ++i) ScriptDriver::onLogChar(buf[i]);
    }
  }
  operator bool() const { return true; }
};

extern HWCDC Serial;
