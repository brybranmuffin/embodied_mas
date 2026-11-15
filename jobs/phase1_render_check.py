"""Phase 1 check: connect to a running simulator, reset a scene, save one camera image.

Usage: python phase1_render_check.py <port> <output_dir>
Exits 0 only if an image was saved and is not black.
"""
import sys
import time

import cv2
import numpy as np
from virtualhome.simulation.unity_simulator import UnityCommunication

port, out_dir = sys.argv[1], sys.argv[2]
comm = UnityCommunication(port=port, timeout_wait=120)

# The simulator takes a while to open its HTTP port.
deadline = time.time() + 300
while True:
    try:
        comm.check_connection()
        break
    except Exception as exc:
        if time.time() > deadline:
            sys.exit(f"FAIL: simulator on port {port} never accepted a connection: {exc}")
        time.sleep(5)
print(f"connected to simulator on port {port}")

t0 = time.time()
comm.reset(0)
print(f"reset(0) took {time.time() - t0:.1f}s")

ok, n_cams = comm.camera_count()
print(f"camera_count: ok={ok} n={n_cams}")
if not ok or n_cams < 1:
    sys.exit("FAIL: no cameras after reset")

t0 = time.time()
ok, images = comm.camera_image([0, n_cams // 2], mode="normal", image_width=640, image_height=480)
print(f"camera_image took {time.time() - t0:.1f}s ok={ok} n_images={len(images) if ok else 0}")
if not ok or not images:
    sys.exit(f"FAIL: camera_image returned {images!r}")

worst = None
for i, img in enumerate(images):
    img = np.asarray(img)
    path = f"{out_dir}/camera_{i}.png"
    cv2.imwrite(path, img)
    mean, std = float(img.mean()), float(img.std())
    print(f"saved {path} shape={img.shape} mean={mean:.1f} std={std:.1f}")
    worst = std if worst is None else min(worst, std)

if worst < 2.0:
    sys.exit("FAIL: at least one image is a flat colour (black or blank render)")
print("PASS: non-blank camera images saved")
