#pragma once
#include <cassert>
#include <chrono>
#include <cstdlib>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <string>
#include <thread>

#define PROGMEM
#define ICACHE_RODATA_ATTR
#define IRAM_ATTR
#define DRAM_ATTR
#define RTC_NOINIT_ATTR
#define PGM_P const char *
#define PSTR(s) (s)

inline unsigned long millis() {
  using namespace std::chrono;
  static const auto start = steady_clock::now();
  return duration_cast<milliseconds>(steady_clock::now() - start).count();
}

inline unsigned long micros() {
  using namespace std::chrono;
  static const auto start = steady_clock::now();
  return duration_cast<microseconds>(steady_clock::now() - start).count();
}

inline void delay(unsigned long ms) {
  std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}
inline void yield() { std::this_thread::yield(); }

// Native builds have no GPIO pins. Treat every input as released, matching the
// idle pull-up state used by the button diagnostics in firmware startup.
inline int digitalRead(int /*pin*/) { return 1; }

#include "HardwareSerial.h"
#include "Print.h"
#include "WString.h"

// The host has no heap ceiling worth speaking of, so every firmware guard that
// asks how much is left is unreachable here -- and those guards protect exactly
// the paths that put a device on the floor. CROSSPOINT_SIM_FREE_HEAP makes this
// stub report a chosen number of bytes for a window, so a test can drive a
// device-only branch: _AFTER_MS is when the pressure starts and _FOR_MS how
// long it lasts, after which the stub reports the host's usual plenty again.
//
// It REPORTS a number, it does not impose one. An allocation the firmware would
// have refused on a device still succeeds here, so a harness built on this can
// show that a guard fires and what it does -- never that the work then fits.
inline uint32_t simulatedFreeHeap() {
  static const uint32_t pressureBytes = [] {
    const char *env = std::getenv("CROSSPOINT_SIM_FREE_HEAP");
    return env && env[0] ? static_cast<uint32_t>(std::strtoul(env, nullptr, 10))
                         : 0u;
  }();
  static const unsigned long afterMs = [] {
    const char *env = std::getenv("CROSSPOINT_SIM_FREE_HEAP_AFTER_MS");
    return env && env[0] ? std::strtoul(env, nullptr, 10) : 0ul;
  }();
  static const unsigned long forMs = [] {
    const char *env = std::getenv("CROSSPOINT_SIM_FREE_HEAP_FOR_MS");
    return env && env[0] ? std::strtoul(env, nullptr, 10) : 0ul;
  }();

  constexpr uint32_t HOST_PLENTY = 1024 * 1024;
  if (pressureBytes == 0)
    return HOST_PLENTY;
  const unsigned long now = millis();
  if (now < afterMs)
    return HOST_PLENTY;
  if (forMs != 0 && now >= afterMs + forMs)
    return HOST_PLENTY;
  return pressureBytes;
}

struct ESPMock {
  uint32_t getFreeHeap() { return simulatedFreeHeap(); }
  void restart() {}
  uint32_t getHeapSize() { return 1024 * 1024; }
  uint32_t getMinFreeHeap() { return simulatedFreeHeap(); }
  // Deliberately not driven by the knob above. The firmware asks for the largest
  // single block in places that have nothing to do with the chapter build under
  // test (the dictionary, the image decoders), and starving those as a side
  // effect would fail a harness somewhere far from what it is checking.
  uint32_t getMaxAllocHeap() { return 1024 * 1024; }
};
extern ESPMock ESP;

inline long random(long max) { return std::rand() % max; }

template <typename A, typename B>
constexpr auto max(A a, B b) -> decltype(a > b ? a : b) {
  return a > b ? a : b;
}
template <typename A, typename B>
constexpr auto min(A a, B b) -> decltype(a < b ? a : b) {
  return a < b ? a : b;
}
