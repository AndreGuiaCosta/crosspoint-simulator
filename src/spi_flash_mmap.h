#pragma once

// SPI flash sector size on every supported ESP chip. Used as the erase
// granularity for partition operations.
#ifndef SPI_FLASH_SEC_SIZE
#define SPI_FLASH_SEC_SIZE 4096
#endif
