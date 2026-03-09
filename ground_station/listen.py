"""
Simple example program that listens for MIN frames and reassembles JPEG images
sent as START (ID=10), CHUNK (ID=11), END (ID=12).
"""
import sys
sys.path.append(r"third_party/min/host/")
from struct import unpack
from time import sleep, time

from min import MINTransportSerial

# Windows randomly assigns COM ports, depending on the driver for the USB serial chip.
MIN_PORT = 'COM6'

# Must match flight-side: MAX_PAYLOAD=255, CHUNK header=4 bytes => 251 data bytes per chunk
CHUNK_DATA_MAX = 251

# Reassembly state
rx = {
    "image_id": None,
    "total_len": None,
    "buf": None,
    "got": set(),
}

print("Program Mark 1")


def u16_le(b, i=0):
    return b[i] | (b[i + 1] << 8)


def u32_le(b, i=0):
    return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)


def bytes_to_int32(data: bytes, big_endian=True) -> int:
    if len(data) != 4:
        raise ValueError("int32 shoud be exactly 4 bytes")
    if big_endian:
        return unpack('>I', data)[0]
    else:
        return unpack('<I', data)[0]


print("Program Mark 2")


def wait_for_frames(min_handler: MINTransportSerial):
    while True:
        frames = min_handler.poll()
        if frames:
            return frames


def handle_frame(min_id: int, payload: bytes):
    """
    Handle one received MIN frame.
    Protocol:
      ID 10 (START): [image_id:u16][total_len:u32]
      ID 11 (CHUNK): [image_id:u16][seq:u16][data...]
      ID 12 (END):   [image_id:u16][total_chunks:u16]
    """
    global rx

    if min_id == 10:  # START
        image_id = u16_le(payload, 0)
        total_len = u32_le(payload, 2)

        rx["image_id"] = image_id
        rx["total_len"] = total_len
        rx["buf"] = bytearray(total_len)
        rx["got"] = set()

        print(f"[START] image_id={image_id} total_len={total_len}")

    elif min_id == 11:  # CHUNK
        # Ignore chunks until we see START
        if rx["buf"] is None:
            return

        image_id = u16_le(payload, 0)
        seq = u16_le(payload, 2)
        data = payload[4:]

        # Ignore chunks from a different image_id
        if image_id != rx["image_id"]:
            return

        offset = seq * CHUNK_DATA_MAX
        end = min(offset + len(data), rx["total_len"])

        # Guard against weird seq values
        if offset >= rx["total_len"]:
            return

        rx["buf"][offset:end] = data[: (end - offset)]
        rx["got"].add(seq)

        # Optional progress output
        # if seq % 10 == 0:
        #     print(f"[CHUNK] seq={seq} bytes={len(data)}")

    elif min_id == 12:  # END
        # Ignore END until we see START
        if rx["buf"] is None:
            return

        image_id = u16_le(payload, 0)
        total_chunks = u16_le(payload, 2)

        # Ignore END from a different image_id
        if image_id != rx["image_id"]:
            return

        missing = [i for i in range(total_chunks) if i not in rx["got"]]
        print(f"[END] image_id={image_id} chunks={total_chunks} missing={len(missing)}")

        out = f"rx_{image_id}.jpg"
        with open(out, "wb") as f:
            f.write(rx["buf"])

        print(f"[OK] wrote {out}")

        # Reset for next image burst
        rx["image_id"] = None
        rx["total_len"] = None
        rx["buf"] = None
        rx["got"] = set()

    else:
        # Other MIN IDs: print if you want
        # print(f"[OTHER] min_id={min_id} payload_len={len(payload)}")
        pass


print("Program Mark 3")


if __name__ == "__main__":
    min_handler = MINTransportSerial(port=MIN_PORT, baudrate=19200)

    while True:
        # Wait for frames and process them
        for frame in wait_for_frames(min_handler):
            # If you still want raw visibility, uncomment:
            # print(f"Frame received: min ID={frame.min_id} payload_len={len(frame.payload)}")

            handle_frame(frame.min_id, frame.payload)

        # Small sleep is fine; poll() is already doing timeouts internally
        sleep(0.01)


print("Program Mark 4")
