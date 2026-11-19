import asyncio
import base64
import hashlib
import struct
import traceback
import time

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

# Interval penerusan data sensor ke Chrome (dalam detik)
FORWARD_INTERVAL_SECONDS = 5.0

def fix_mqtt_packet(payload: bytes) -> bytes:
    if len(payload) >= 10 and payload[0] == 0x10:
        if b"MQTT" in payload[2:8]:
            flags = payload[9]
            will_flag = (flags & 0x04) != 0
            will_qos = (flags & 0x18) != 0
            if not will_flag and will_qos:
                fixed_flags = flags & ~0x18
                payload = payload[:9] + bytes([fixed_flags]) + payload[10:]
                print(f"[Bridge] Berhasil memperbaiki Connect Flag (0x{flags:02x} -> 0x{fixed_flags:02x})")
    return payload

async def handle_ws_client(ws_reader, ws_writer):
    peer = ws_writer.get_extra_info("peername")
    print(f"\n==================================================")
    print(f"[Bridge] Koneksi baru dari Chrome: {peer}")

    # 1. Read HTTP Handshake
    request = b""
    while b"\r\n\r\n" not in request:
        chunk = await ws_reader.read(1024)
        if not chunk:
            print("[Bridge] Koneksi terputus saat membaca handshake.")
            return
        request += chunk

    headers = {}
    lines = request.decode("latin1", errors="ignore").split("\r\n")
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()

    key = headers.get("sec-websocket-key")
    if not key:
        print("[Bridge] Header Sec-WebSocket-Key tidak ditemukan.")
        ws_writer.close()
        return

    accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
    subprotocol = headers.get("sec-websocket-protocol", "")
    req_protocols = [p.strip() for p in subprotocol.split(",") if p.strip()]

    resp_lines = [
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
        f"Sec-WebSocket-Accept: {accept}",
    ]
    if req_protocols:
        resp_lines.append(f"Sec-WebSocket-Protocol: {req_protocols[0]}")
    resp_lines.append("")
    resp_lines.append("")

    response = "\r\n".join(resp_lines).encode("latin1")
    ws_writer.write(response)
    await ws_writer.drain()
    print(f"[Bridge] Handshake 101 Sukses! Subprotocol: {req_protocols[0] if req_protocols else 'None'}")

    # 2. Connect to local TCP Mosquitto on 1883
    try:
        tcp_reader, tcp_writer = await asyncio.open_connection("127.0.0.1", 1883)
        print(f"[Bridge] Terhubung ke Mosquitto (127.0.0.1:1883)!")
        print(f"[Bridge] Throttle aktif: Data sensor akan diteruskan tiap {FORWARD_INTERVAL_SECONDS} detik.")
    except Exception as e:
        print(f"[Bridge] Gagal konek ke Mosquitto: {e}")
        ws_writer.close()
        return

    last_forward_time = 0.0

    async def ws_to_tcp():
        try:
            while True:
                header = await ws_reader.readexactly(2)
                b1, b2 = header[0], header[1]
                opcode = b1 & 0x0F
                has_mask = (b2 & 0x80) != 0
                payload_len = b2 & 0x7F

                if opcode == 0x8:  # Close
                    print("[Bridge] Chrome menutup koneksi WebSocket.")
                    break
                elif opcode == 0x9:  # Ping
                    ws_writer.write(bytes([0x8A, 0x00]))
                    await ws_writer.drain()
                    continue

                if payload_len == 126:
                    ext = await ws_reader.readexactly(2)
                    payload_len = struct.unpack("!H", ext)[0]
                elif payload_len == 127:
                    ext = await ws_reader.readexactly(8)
                    payload_len = struct.unpack("!Q", ext)[0]

                mask_key = await ws_reader.readexactly(4) if has_mask else None
                payload = await ws_reader.readexactly(payload_len)

                if has_mask:
                    unmasked = bytearray(payload_len)
                    for i in range(payload_len):
                        unmasked[i] = payload[i] ^ mask_key[i % 4]
                    payload = bytes(unmasked)

                payload = fix_mqtt_packet(payload)
                tcp_writer.write(payload)
                await tcp_writer.drain()
        except asyncio.IncompleteReadError:
            pass
        except Exception as e:
            print(f"[Bridge] Error di ws_to_tcp: {e}")
        finally:
            tcp_writer.close()

    async def tcp_to_ws():
        nonlocal last_forward_time
        try:
            while True:
                data = await tcp_reader.read(4096)
                if not data:
                    print("[Bridge] Mosquitto menutup koneksi TCP.")
                    break

                # Deteksi paket PUBLISH MQTT (byte pertama 0x30..0x3F)
                is_publish = (data[0] & 0xF0) == 0x30
                now = time.time()

                if is_publish:
                    # Filter agar hanya dikirim ke Chrome setiap 5 detik
                    if (now - last_forward_time) < FORWARD_INTERVAL_SECONDS and last_forward_time != 0.0:
                        continue
                    last_forward_time = now

                length = len(data)
                if length <= 125:
                    hdr = struct.pack("!BB", 0x82, length)
                elif length <= 65535:
                    hdr = struct.pack("!BBH", 0x82, 126, length)
                else:
                    hdr = struct.pack("!BBQ", 0x82, 127, length)

                if is_publish:
                    print(f"[Bridge] Mosquitto -> Chrome: {length} bytes [Update tiap 5 detik] OK")

                ws_writer.write(hdr + data)
                await ws_writer.drain()
        except Exception as e:
            print(f"[Bridge] Error di tcp_to_ws: {e}")
        finally:
            ws_writer.close()

    await asyncio.gather(ws_to_tcp(), tcp_to_ws(), return_exceptions=True)
    print(f"[Bridge] Sesi selesai untuk {peer}")
    print(f"==================================================")

async def main():
    server = await asyncio.start_server(handle_ws_client, "0.0.0.0", 9001)
    print("=" * 60)
    print("[Bridge] WebSocket MQTT Bridge AKTIF!")
    print(f"[Bridge] Mode: Pengiriman ke Chrome dibatasi per {FORWARD_INTERVAL_SECONDS} detik")
    print("[Bridge] Port WebSocket : 9001 -> Mosquitto 1883")
    print("=" * 60)
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
