#pragma once

#include "esp_err.h"
#include "esp_partition.h"

// Returns nullptr on host so the SD firmware flash + OTA boot-switch paths
// fall through their nullptr guards into a runtime "not supported" error.
inline const esp_partition_t* esp_ota_get_next_update_partition(const esp_partition_t*) { return nullptr; }
