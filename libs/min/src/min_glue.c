// min_glue.c - Ada-callable wrapper for MIN TX-only proof
// Acts a bridge between the Ada and C languages
#include <stdint.h>
#include <string.h>
#include "min.h"

// Exported by Ada package Image_Store
extern uint8_t image_buf[];

// Set this to your NEORV32 CPU clock (Hz). If unsure, keep 50 MHz for now.
#ifndef NEORV32_CPU_CLK_HZ
#define NEORV32_CPU_CLK_HZ 50000000UL
#endif

static inline uint64_t rdcycle64(void) {
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
    const uint64_t ticks = ((uint64_t)NEORV32_CPU_CLK_HZ / 1000ULL) * (uint64_t)ms;
    const uint64_t start = rdcycle64();
    while ((rdcycle64() - start) < ticks) {
        __asm__ volatile ("nop");
    }
}

// Message IDs
#define MIN_ID_IMG_START  10
#define MIN_ID_IMG_CHUNK  11
#define MIN_ID_IMG_END    12

// Each chunk has 2 bytes image_id and 2 bytes seq
#define CHUNK_HDR_LEN 4u
#define CHUNK_DATA_MAX (MAX_PAYLOAD - CHUNK_HDR_LEN)

// MIN state
static struct min_context g_ctx;

static void put_u16_le(uint8_t *p, uint16_t v) {
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
    min_init_context(&g_ctx, 0);
}

void min_glue_send_image_once(uint32_t image_len) {
    static uint16_t image_id = 1;

    // ---- START ----
    uint8_t start_payload[2 + 4];
    put_u16_le(&start_payload[0], image_id);
    put_u32_le(&start_payload[2], image_len);
    min_send_frame(&g_ctx, MIN_ID_IMG_START, start_payload, (uint8_t)sizeof(start_payload));

    // ---- CHUNKS ----
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
    uint8_t end_payload[2 + 2];
    put_u16_le(&end_payload[0], image_id);
    put_u16_le(&end_payload[2], seq);
    min_send_frame(&g_ctx, MIN_ID_IMG_END, end_payload, (uint8_t)sizeof(end_payload));

    image_id++;
}

// Old test entry point can stay if you want compatibility.
// For now, just leave it empty or keep it if still useful.
void min_glue_send_test(void) {
    // no-op
}

void min_glue_send_image_loop(uint32_t image_len) {
    for (;;) {
        min_glue_send_image_once(image_len);
        delay_ms(10000);
    }
}
