// =============================================================================
// fat.c — FAT12 disk image reader
// =============================================================================
// Reads a FAT12-formatted disk image, parses the BIOS Parameter Block, loads
// the first FAT and the root directory, and looks up a file entry by name.
//
// Usage:
//     fat <disk_image> <file_name>
//
// `file_name` must be passed in 8.3 form, padded with spaces to 11 bytes —
// e.g. "KERNEL  BIN" for kernel.bin. FAT12 stores names this way on disk;
// translating "kernel.bin" → "KERNEL  BIN" is left to the caller for now.
// =============================================================================

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

// Length of a FAT 8.3 directory-entry name (8-char base + 3-char ext, no dot).
#define FAT_NAME_LEN 11

// -----------------------------------------------------------------------------
// On-disk structures.
//
// Both layouts must match what the FAT spec dictates byte-for-byte, so we
// disable padding/reordering with __attribute__((packed)). Without this, the
// compiler would insert alignment holes and our offsets would drift away from
// what's actually on disk.
// -----------------------------------------------------------------------------

typedef struct {
    // --- BIOS Parameter Block (BPB) — common to all FAT variants. ---
    uint8_t  BootJumpInstruction[3];
    uint8_t  OemIdentifier[8];
    uint16_t BytesPerSector;
    uint8_t  SectorsPerCluster;
    uint16_t ReservedSectors;
    uint8_t  FatCount;
    uint16_t DirEntryCount;
    uint16_t TotalSectors;
    uint8_t  MediaDescriptorType;
    uint16_t SectorsPerFat;
    uint16_t SectorsPerTrack;
    uint16_t Heads;
    uint32_t HiddenSectors;
    uint32_t LargeSectorCount;

    // --- Extended Boot Record (FAT12/16 form). ---
    uint8_t  DriveNumber;
    uint8_t  _Reserved;
    uint8_t  Signature;
    uint32_t VolumeId;                  // Serial number; value isn't meaningful.
    uint8_t  VolumeLabel[11];           // Space-padded.
    uint8_t  SystemId[8];

    // The remaining bytes of the boot sector (boot code + 0xAA55 signature)
    // are irrelevant to filesystem parsing and we don't model them here.
} __attribute__((packed)) BootSector;

typedef struct {
    uint8_t  Name[FAT_NAME_LEN];        // 8.3, space-padded, no dot.
    uint8_t  Attributes;                // Read-only / hidden / system / volume / etc.
    uint8_t  _Reserved;
    uint8_t  CreatedTimeTenths;
    uint16_t CreatedTime;
    uint16_t CreatedDate;
    uint16_t AccessedDate;
    uint16_t FirstClusterHigh;          // Always 0 on FAT12/16.
    uint16_t ModifiedTime;
    uint16_t ModifiedDate;
    uint16_t FirstClusterLow;           // Combine with High on FAT32.
    uint32_t Size;                      // File size in bytes.
} __attribute__((packed)) DirectoryEntry;

// -----------------------------------------------------------------------------
// Filesystem state.
//
// Kept as file-scope globals for simplicity. A non-trivial reader would bundle
// these into a context struct threaded through each function — that scales
// better when you start handling multiple mounts or recursive directory walks.
// -----------------------------------------------------------------------------

static BootSector       g_BootSector;
static uint8_t*         g_Fat           = NULL;
static DirectoryEntry*  g_RootDirectory = NULL;

// -----------------------------------------------------------------------------
// readBootSector — read sector 0 into g_BootSector.
// Returns true on success.
// -----------------------------------------------------------------------------
static bool readBootSector(FILE* disk) {
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) == 1;
}

// -----------------------------------------------------------------------------
// readSectors — read `count` sectors starting at LBA `lba` into `bufferOut`.
//
// Uses BytesPerSector from the (already-loaded) boot sector to translate
// LBA → byte offset. The caller is responsible for sizing the buffer correctly.
// -----------------------------------------------------------------------------
static bool readSectors(FILE* disk, uint32_t lba, uint32_t count, void* bufferOut) {
    if (fseek(disk, (long)lba * g_BootSector.BytesPerSector, SEEK_SET) != 0) {
        return false;
    }
    return fread(bufferOut, g_BootSector.BytesPerSector, count, disk) == count;
}

// -----------------------------------------------------------------------------
// readFat — load the first FAT into g_Fat.
//
// On-disk layout: [reserved sectors][FAT 1][FAT 2 (backup)][root dir][data].
// We only read FAT 1; FAT 2 is a redundant copy maintained by the OS.
// -----------------------------------------------------------------------------
static bool readFat(FILE* disk) {
    size_t fatBytes = (size_t)g_BootSector.SectorsPerFat * g_BootSector.BytesPerSector;
    g_Fat = (uint8_t*)malloc(fatBytes);
    if (!g_Fat) {
        fprintf(stderr, "Out of memory allocating %zu bytes for FAT\n", fatBytes);
        return false;
    }
    return readSectors(disk, g_BootSector.ReservedSectors,
                       g_BootSector.SectorsPerFat, g_Fat);
}

// -----------------------------------------------------------------------------
// readRootDirectory — load the root directory into g_RootDirectory.
//
// The root directory immediately follows the FATs. Its size is fixed at
// format time (DirEntryCount entries × 32 bytes) and rounded up to a whole
// number of sectors so readSectors stays sector-aligned.
// -----------------------------------------------------------------------------
static bool readRootDirectory(FILE* disk) {
    uint32_t lba = g_BootSector.ReservedSectors
                 + (uint32_t)g_BootSector.SectorsPerFat * g_BootSector.FatCount;

    // NB: the original code had `sizeof(DirectoryEntry) + DirEntryCount`,
    // which produced a 256-byte buffer instead of ~7 KiB and miscounted
    // sectors. The correct expression multiplies entry size by entry count.
    uint32_t size = (uint32_t)sizeof(DirectoryEntry) * g_BootSector.DirEntryCount;
    uint32_t sectors = size / g_BootSector.BytesPerSector;
    if (size % g_BootSector.BytesPerSector != 0) {
        sectors++;
    }

    size_t allocBytes = (size_t)sectors * g_BootSector.BytesPerSector;
    g_RootDirectory = (DirectoryEntry*)malloc(allocBytes);
    if (!g_RootDirectory) {
        fprintf(stderr, "Out of memory allocating %zu bytes for root directory\n",
                allocBytes);
        return false;
    }
    return readSectors(disk, lba, sectors, g_RootDirectory);
}

// -----------------------------------------------------------------------------
// findFile — look up a file by its 11-byte 8.3 name.
//
// `name` must point to exactly FAT_NAME_LEN bytes in 8.3 padded form
// (e.g. "KERNEL  BIN" — uppercase, space-padded, no dot). Returns a pointer
// into g_RootDirectory, or NULL if no entry matches.
// -----------------------------------------------------------------------------
static DirectoryEntry* findFile(const char* name) {
    for (uint32_t i = 0; i < g_BootSector.DirEntryCount; i++) {
        if (memcmp(name, g_RootDirectory[i].Name, FAT_NAME_LEN) == 0) {
            return &g_RootDirectory[i];
        }
    }
    return NULL;
}

// -----------------------------------------------------------------------------
// main
// -----------------------------------------------------------------------------
int main(int argc, char** argv) {
    if (argc < 3) {
        printf("Syntax: %s <disk image> <file name>\n", argv[0]);
        return 1;
    }

    int rc = 0;
    FILE* disk = fopen(argv[1], "rb");
    if (!disk) {
        fprintf(stderr, "Cannot open disk image %s\n", argv[1]);
        return 1;
    }

    if (!readBootSector(disk)) {
        fprintf(stderr, "Could not read boot sector!\n");
        rc = 2;
        goto cleanup;
    }

    if (!readFat(disk)) {
        fprintf(stderr, "Could not read FAT!\n");
        rc = 3;
        goto cleanup;
    }

    if (!readRootDirectory(disk)) {
        fprintf(stderr, "Could not read root directory!\n");
        rc = 4;
        goto cleanup;
    }

    DirectoryEntry* fileEntry = findFile(argv[2]);
    if (!fileEntry) {
        fprintf(stderr, "Could not find file %s!\n", argv[2]);
        rc = 5;
        goto cleanup;
    }

    printf("Found %s: %u bytes, first cluster %u\n",
           argv[2], fileEntry->Size, fileEntry->FirstClusterLow);

cleanup:
    // free(NULL) is a no-op, so this is safe even if some allocations
    // never happened (e.g. we bailed out before readFat).
    free(g_Fat);
    free(g_RootDirectory);
    fclose(disk);
    return rc;
}
