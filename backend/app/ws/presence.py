from fastapi import WebSocket


async def presence_socket(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            data = await ws.receive_text()
            await ws.send_json({"status": "ok", "payload": data})
    finally:
        await ws.close()
