#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import zmq
import numpy as np
import time
import cv2
import struct
from multiprocessing import shared_memory
from collections import deque
from rich import print

class VisionClient:
    def __init__(
        self,
        server_address="127.0.0.1",
        port=5555,
        img_shape=None,
        img_shm_name=None,
        unit_test=False,
        image_show=False,
        depth_show=False
    ):
        self.server_address = server_address
        self.port = port
        self.running = True
        self.image_show = image_show
        
        # Target Output Shape (Height, Width, Channels)
        self.img_shape = img_shape 
        
        # Shared Memory
        self.img_shm_name = img_shm_name
        self.img_shm_enabled = False
        if (self.img_shape is not None) and (self.img_shm_name is not None):
            try:
                self.img_shm = shared_memory.SharedMemory(name=self.img_shm_name)
                self.img_array = np.ndarray(self.img_shape, dtype=np.uint8, buffer=self.img_shm.buf)
                self.img_shm_enabled = True
            except FileNotFoundError:
                print(f"[VisionClient] Warning: Shared memory '{self.img_shm_name}' not found.")

        self.unit_test = unit_test
        if self.unit_test: self._init_performance_metrics()

    def _init_performance_metrics(self):
        self.frame_count = 0
        self.start_time = time.time()
        self.time_window = 1.0
        self.frame_times = deque()

    def _update_performance_metrics(self, print_info):
        if not self.unit_test: return
        now = time.time()
        self.frame_times.append(now)
        while self.frame_times and self.frame_times[0] < now - self.time_window:
            self.frame_times.popleft()
        self.frame_count += 1
        
        if self.frame_count % 30 == 0:
            fps = len(self.frame_times) / self.time_window
            print(f"[VisionClient] FPS: {fps:.2f} | {print_info}")

    def receive_process(self):
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.SUB)
        
        # Use CONFLATE to always get the newest frame (low latency)
        self.socket.setsockopt(zmq.CONFLATE, 1)
        
        self.socket.connect(f"tcp://{self.server_address}:{self.port}")
        self.socket.setsockopt(zmq.SUBSCRIBE, b"")

        print(f"[VisionClient] JPEG Client Started. Target Output: {self.img_shape}")

        try:
            while self.running:
                try:
                    # 1. Receive Compressed Data
                    message = self.socket.recv()
                    
                    if len(message) < 12: continue

                    # 2. Parse Header [Width][Height][JPEG_SIZE]
                    w_orig = struct.unpack('i', message[0:4])[0]
                    h_orig = struct.unpack('i', message[4:8])[0]
                    jpeg_size = struct.unpack('i', message[8:12])[0]
                    
                    # Validation
                    if len(message) - 12 != jpeg_size:
                        continue

                    # 3. Decode JPEG (This is the "heavy" lifting)
                    # Use np.frombuffer to create a view, then decode
                    jpg_data = np.frombuffer(message, dtype=np.uint8, offset=12)
                    decoded_img = cv2.imdecode(jpg_data, cv2.IMREAD_COLOR)

                    if decoded_img is None: continue

                    # 4. Resize to Target (1280x360)
                    if self.img_shape is not None:
                        target_h, target_w = self.img_shape[0], self.img_shape[1]
                        
                        # Only resize if necessary
                        if (decoded_img.shape[1] != target_w) or (decoded_img.shape[0] != target_h):
                            final_img = cv2.resize(decoded_img, (target_w, target_h), interpolation=cv2.INTER_LINEAR)
                        else:
                            final_img = decoded_img
                    else:
                        final_img = decoded_img

                    # 5. Shared Memory Copy
                    if self.img_shm_enabled:
                        np.copyto(self.img_array, final_img)

                    # 6. Display
                    if self.image_show:
                        cv2.imshow("VisionClient (JPEG Stream)", final_img)
                        if (cv2.waitKey(1) & 0xFF) == ord('q'):
                            self.running = False
                            
                    self._update_performance_metrics(f"Orig: {w_orig}x{h_orig} -> JPEG Size: {jpeg_size/1024:.1f} KB")

                except zmq.Again:
                    continue

        except KeyboardInterrupt:
            pass
        finally:
            self._close()

    def _close(self):
        self.socket.close()
        self.context.term()
        if self.image_show: cv2.destroyAllWindows()
        print("[VisionClient] Closed.")

if __name__ == "__main__":
    import threading
    
    num_cameras = 2
    # Target: 1280x360
    target_shape = (360, 640 * num_cameras, 3) 
    
    try:
        shm_size = int(np.prod(target_shape) * np.uint8().itemsize)
        image_shared_memory = shared_memory.SharedMemory(create=True, size=shm_size)
        image_shm_name = image_shared_memory.name
    except FileExistsError:
        image_shm_name = "psm_img_00" 

    client = VisionClient(
        server_address="192.168.123.164", 
        port=5555,
        img_shape=target_shape,
        img_shm_name=image_shm_name,
        image_show=True,
        unit_test=True
    )
    
    vision_thread = threading.Thread(target=client.receive_process, daemon=True)
    vision_thread.start()
    
    try:
        while True: time.sleep(1)
    except KeyboardInterrupt: pass
    finally:
        try:
            image_shared_memory.close()
            image_shared_memory.unlink()
        except: pass