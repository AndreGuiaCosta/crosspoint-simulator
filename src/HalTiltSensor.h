#pragma once
#include <cstdint>

// Simulator stub for HalTiltSensor. Tilt gestures aren't simulated; all
// query methods return false / no-activity so the reader's tilt-page-turn
// path is inert.

namespace CrossPointOrientation {
enum Value : uint8_t { PORTRAIT = 0, LANDSCAPE_CW = 1, INVERTED = 2, LANDSCAPE_CCW = 3 };
}

namespace CrossPointTiltPageTurn {
enum Value : uint8_t { TILT_OFF = 0, TILT_NORMAL = 1, TILT_INVERTED = 2 };
}

class HalTiltSensor {
 public:
  void begin() {}
  bool wake() { return true; }
  bool deepSleep() { return true; }
  bool isAvailable() const { return false; }
  void update(uint8_t /*mode*/, uint8_t /*orientation*/, bool /*inReader*/) {}
  bool wasTiltedForward() { return false; }
  bool wasTiltedBack() { return false; }
  bool hadActivity() { return false; }
  void clearPendingEvents() {}
};

extern HalTiltSensor halTiltSensor;
