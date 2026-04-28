#include <ReadestTlsConfig.h>
#include <WiFiClientSecure.h>

// Simulator-side override for the firmware's CA-bundle path (`src/test_hooks/
// ReadestTlsConfig.cpp`). The firmware's version is excluded from the
// simulator build via `build_src_filter` in `platformio.local.ini` and this
// implementation is linked in instead. setInsecure() is acceptable here
// because the simulator's WiFiClientSecure stub doesn't actually verify
// certificates and the embedded CA bundle symbol doesn't exist on host.
namespace ReadestTls {
void configure(WiFiClientSecure& client) { client.setInsecure(); }
}  // namespace ReadestTls
