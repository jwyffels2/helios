// min_glue.c - Ada-callable wrapper for MIN image transport.
//
// Ada owns the high-level camera and application flow, while the MIN protocol
// implementation is C. This file is the bridge: Ada calls these exported C
// functions, and this file packages bytes from Image_Store.image_buf into MIN
// START/CHUNK/END frames.
#include <stdint.h>
#include <string.h>
#include "min.h"

// The application exports image_buf from Ada Image_Store. Tests link this C
// module without the application, so keep a weak fallback to satisfy the linker.
uint8_t image_buf[1] __attribute__((weak));

// Set this to your NEORV32 CPU clock (Hz). If unsure, keep 50 MHz for now.
#ifndef NEORV32_CPU_CLK_HZ
#define NEORV32_CPU_CLK_HZ 50000000UL
#endif

static inline uint64_t rdcycle64(void) {
    // RV32 reads the 64-bit cycle counter as high/low/high. If the high half
    // changes while reading the low half, reread low so the result is stable.
    uint32_t hi0, lo, hi1;
    __asm__ volatile ("rdcycleh %0" : "=r"(hi0));
    __asm__ volatile ("rdcycle  %0" : "=r"(lo));
    __asm__ volatile ("rdcycleh %0" : "=r"(hi1));
    if (hi0 != hi1) {
        __asm__ volatile ("rdcycle  %0" : "=r"(lo));
        hi0 = hi1;
    }
    return ((uint64_t)hi0 << 32) | lo;
}

static void delay_ms(uint32_t ms) {
    // The demo loop uses a cycle-counter busy wait instead of timers so this C
    // layer stays independent from the Ada board support packages.
    const uint64_t ticks = ((uint64_t)NEORV32_CPU_CLK_HZ / 1000ULL) * (uint64_t)ms;
    const uint64_t start = rdcycle64();
    while ((rdcycle64() - start) < ticks) {
        __asm__ volatile ("nop");
    }
}

// Message IDs used by the receiver to reconstruct one image transfer.
// START announces image_id and total length, CHUNK carries ordered slices, END
// announces the final sequence number.
#define MIN_ID_IMG_START  10
#define MIN_ID_IMG_CHUNK  11
#define MIN_ID_IMG_END    12

// Each chunk has 2 bytes image_id and 2 bytes seq
#define CHUNK_HDR_LEN 4u
#define CHUNK_DATA_MAX (MAX_PAYLOAD - CHUNK_HDR_LEN)

// MIN state
static struct min_context g_ctx;

static void put_u16_le(uint8_t *p, uint16_t v) {
    // Payloads use little-endian integers because both sides of this prototype
    // are simple byte readers and the order is easy to decode on the ground.
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
}

static void put_u32_le(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
    p[2] = (uint8_t)((v >> 16) & 0xFF);
    p[3] = (uint8_t)((v >> 24) & 0xFF);
}

void min_glue_init(void) {
    // MIN contexts hold protocol framing state. Port 0 matches the single
    // transport path implemented by min_port.c in this project.
    min_init_context(&g_ctx, 0);
}

void min_glue_send_image_once(uint32_t image_len) {
    // Send exactly one image burst. The image_id increments per burst so the
    // receiver can tell whether chunks belong to the same capture.
    static uint16_t image_id = 1;

    // ---- START ----
    // Layout: image_id:u16, total_image_length:u32.
    uint8_t start_payload[2 + 4];
    put_u16_le(&start_payload[0], image_id);
    put_u32_le(&start_payload[2], image_len);
    min_send_frame(&g_ctx, MIN_ID_IMG_START, start_payload, (uint8_t)sizeof(start_payload));

    // ---- CHUNKS ----
    // Layout: image_id:u16, sequence:u16, payload bytes. Chunks are capped by
    // MAX_PAYLOAD so MIN framing never exceeds the protocol limit.
    uint32_t offset = 0;
    uint16_t seq = 0;
    uint8_t chunk_payload[MAX_PAYLOAD];

    while (offset < image_len) {
        uint32_t remaining = image_len - offset;
        uint8_t n = (remaining > CHUNK_DATA_MAX) ? (uint8_t)CHUNK_DATA_MAX : (uint8_t)remaining;

        put_u16_le(&chunk_payload[0], image_id);
        put_u16_le(&chunk_payload[2], seq);
        memcpy(&chunk_payload[4], &image_buf[offset], n);

        min_send_frame(&g_ctx, MIN_ID_IMG_CHUNK, chunk_payload, (uint8_t)(CHUNK_HDR_LEN + n));

        offset += n;
        seq++;
    }

    // ---- END ----
    // Layout: image_id:u16, final_sequence:u16. The receiver can compare the
    // final sequence to the number of chunks it accepted.
    uint8_t end_payload[2 + 2];
    put_u16_le(&end_payload[0], image_id);
    put_u16_le(&end_payload[2], seq);
    min_send_frame(&g_ctx, MIN_ID_IMG_END, end_payload, (uint8_t)sizeof(end_payload));

    image_id++;
}

void min_glue_send_test(void) {
    // Backward-compatible no-op for older Ada test code that only checked that
    // the MIN glue could be called from Ada.
    // no-op
}

void min_glue_send_image_loop(uint32_t image_len) {
    // Convenience demo loop. Production command handling should usually call
    // min_glue_send_image_once so the application stays responsive.
    for (;;) {
        min_glue_send_image_once(image_len);
        delay_ms(10000);
    }
}
