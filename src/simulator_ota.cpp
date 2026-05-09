#include <Logging.h>

#include "network/OtaUpdater.h"

bool OtaUpdater::isUpdateNewer() const { return false; }
const std::string& OtaUpdater::getLatestVersion() const {
  static const std::string version = CROSSPOINT_VERSION;
  return version;
}

OtaUpdater::OtaUpdaterError OtaUpdater::checkForUpdate() {
  LOG_DBG("OTA", "[EMU] OTA check is non-destructive; reporting no update");
  return NO_UPDATE;
}

OtaUpdater::OtaUpdaterError OtaUpdater::installUpdate(ProgressCallback onProgress, void* ctx) {
  LOG_DBG("OTA", "[EMU] OTA install is not supported in the native emulator");
  processedSize = 1;
  totalSize = 1;
  if (onProgress) onProgress(ctx);
  return INTERNAL_UPDATE_ERROR;
}
