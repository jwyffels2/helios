// min_port.c - NEORV32/Basys3 UART0 "port" for MIN (TX-only proof)

#include <stdint.h>
#include "min.h"

// Implemented by Ada (Uart0.Put_Char), exported as "putchar"
extern void putchar(char c);

// TX buffer space available.
// For now: "huge" because Ada putchar blocks until FIFO has room.
// This makes min_send_frame always attempt to send.
uint16_t min_tx_space(uint8_t port) {
    (void)port;
    return 0xFFFF;
}

void min_tx_start(uint8_t port) {
    (void)port;
    // no-op (optional)
}

void min_tx_byte(uint8_t port, uint8_t byte) {
    (void)port;
    putchar((char)byte);
}

void min_tx_finished(uint8_t port) {
    (void)port;
    // no-op (optional)
}

// min.c references this symbol even if unused
void min_application_handler(uint8_t min_id, uint8_t const *min_payload, uint8_t len_payload, uint8_t port) {
    (void)min_id; (void)min_payload; (void)len_payload; (void)port;
    // no-op for TX-only proof
}

uint32_t min_time_ms(void) {
    return 0;
}
