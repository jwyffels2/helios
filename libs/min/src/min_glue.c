// min_glue.c - Ada-callable wrapper for MIN TX-only proof
// Acts a bridge between the Ada and C languages
#include <stdint.h>
#include <string.h>
#include "min.h"
#include "test_jpeg.h"

// START DELAY
// This is for the delay, not needed
// Set this to your NEORV32 CPU clock (Hz). If unsure, keep 50 MHz for now.
#ifndef NEORV32_CPU_CLK_HZ
#define NEORV32_CPU_CLK_HZ 50000000UL
#endif

static inline uint64_t rdcycle64(void) {
  uint32_t hi0, lo, hi1;
  // Safe 64-bit read on RV32: read hi/lo/hi until stable
  __asm__ volatile ("rdcycleh %0" : "=r"(hi0));
  __asm__ volatile ("rdcycle  %0" : "=r"(lo));
  __asm__ volatile ("rdcycleh %0" : "=r"(hi1));
  if (hi0 != hi1) {
    // rollover happened; reread
    __asm__ volatile ("rdcycle  %0" : "=r"(lo));
    hi0 = hi1;
  }
  return ((uint64_t)hi0 << 32) | lo;
}

// Busy-wait delay using cycle counter
static void delay_ms(uint32_t ms) {
  const uint64_t ticks = ((uint64_t)NEORV32_CPU_CLK_HZ / 1000ULL) * (uint64_t)ms;
  const uint64_t start = rdcycle64();
  while ((rdcycle64() - start) < ticks) {
    __asm__ volatile ("nop");
  }
}
// END DELAY

// Message ID's
#define MIN_ID_IMG_START  10
#define MIN_ID_IMG_CHUNK  11
#define MIN_ID_IMG_END    12

// Each chunk has 2 bytes header and 2 bytes seq for 4 bytes total.
// Max payload - 4 - CHUNK_DATA_MAX
#define CHUNK_HDR_LEN 4u
#define CHUNK_DATA_MAX (MAX_PAYLOAD - CHUNK_HDR_LEN)

// Min context
// State machine + buffer
static struct min_context g_ctx;

// Write integers into a buffer in little endian format
static void put_u16_le(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
}

// Write integers into a buffer in little endian format
static void put_u32_le(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
    p[2] = (uint8_t)((v >> 16) & 0xFF);
    p[3] = (uint8_t)((v >> 24) & 0xFF);
}

// Initializes state machine in g_ctx at port 0.
void min_glue_init(void) {
    min_init_context(&g_ctx, 0); // port 0
}

// Test image sender
void min_glue_send_test(void) {

    // Must persist so that we can increment it between calls
    static uint16_t image_id = 1;

    // ---- START ----
    // Allocate a byte buffer
    uint8_t start_payload[2 + 4];
    // Bytes 0 - 1 are image_id
    put_u16_le(&start_payload[0], image_id);
    // Bytes 2 - 5 are total length of image
    put_u32_le(&start_payload[2], test_jpeg_len);
    // Send the frame with an id of 10
    min_send_frame(&g_ctx, MIN_ID_IMG_START, start_payload, (uint8_t)sizeof(start_payload));

    // ---- CHUNKS ----
    // Track offset
    uint32_t offset = 0;
    // Track sequence number
    uint16_t seq = 0;

    // Create a worse case buffer
    uint8_t chunk_payload[MAX_PAYLOAD];

    while (offset < test_jpeg_len) {
        // Compute remaining number of bytes
        uint32_t remaining = test_jpeg_len - offset;
        // Set n to the number of remaining bytes or the max value
        uint8_t n = (remaining > CHUNK_DATA_MAX) ? (uint8_t)CHUNK_DATA_MAX : (uint8_t)remaining;

        // Bytes 0 - 1 are image_id
        put_u16_le(&chunk_payload[0], image_id);
        // Bytes 2 - 3 are sequence number
        put_u16_le(&chunk_payload[2], seq);
        // Remaining are jpeg data slice
        memcpy(&chunk_payload[4], &test_jpeg[offset], n);

        // Send the frame with an id of 11
        min_send_frame(&g_ctx, MIN_ID_IMG_CHUNK, chunk_payload, (uint8_t)(CHUNK_HDR_LEN + n));

        // Increment offset and sequence number
        offset += n;
        seq++;
    }

    // ---- END ----
    // Allocate a byte buffer
    uint8_t end_payload[2 + 2];
    // Bytes 0 - 1 are image_id
    put_u16_le(&end_payload[0], image_id);
    // Bytes 2 - 3 are sequence number
    put_u16_le(&end_payload[2], seq);
    // Send the frame with an id of 12
    min_send_frame(&g_ctx, MIN_ID_IMG_END, end_payload, (uint8_t)sizeof(end_payload));

    // Increment so the next call generates a new image
    image_id++;

    // Wait a few seconds before sending the next image burst
    // Dev only, delete once finished.
    delay_ms(10000);

}
