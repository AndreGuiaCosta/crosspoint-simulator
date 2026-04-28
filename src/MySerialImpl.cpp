#include <Logging.h>

#include <cstdarg>
#include <cstdio>

// Simulator-side definitions for MySerialImpl. On real ESP32, Arduino-ESP32's
// framework symbols + LTO/--gc-sections satisfy these references at link
// time; the firmware's lib/Logging/Logging.cpp doesn't ship explicit
// definitions. The native (simulator) link has no such resolution path, so
// we provide them here. Each method just forwards to logSerial (the
// underlying HWCDC), matching the intent of the inline declarations in
// lib/Logging/Logging.h.

constexpr int kMaxEntryLen = 256;

MySerialImpl MySerialImpl::instance;

size_t MySerialImpl::write(uint8_t b) { return logSerial.write(b); }
size_t MySerialImpl::write(const uint8_t* buffer, size_t size) { return logSerial.write(buffer, size); }
void MySerialImpl::flush() { logSerial.flush(); }

size_t MySerialImpl::printf(const char* format, ...) {
  va_list args;
  va_start(args, format);
  char buf[kMaxEntryLen];
  const int n = vsnprintf(buf, sizeof(buf), format, args);
  va_end(args);
  if (n <= 0) return 0;
  const size_t toWrite = static_cast<size_t>(n) < sizeof(buf) ? static_cast<size_t>(n) : sizeof(buf) - 1;
  return logSerial.write(reinterpret_cast<const uint8_t*>(buf), toWrite);
}
