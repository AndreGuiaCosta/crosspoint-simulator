#include <SimulatorTextInput.h>

#include "ScriptDriver.h"

// Simulator-side override for the firmware's no-op (`src/test_hooks/
// SimulatorTextInput.cpp`). The firmware's no-op is excluded from the
// simulator build via `build_src_filter` in `platformio.local.ini` and
// this implementation is linked in instead.
namespace SimulatorTextInput {
std::string consumeQueuedText() { return ScriptDriver::consumeQueuedText(); }
}  // namespace SimulatorTextInput
