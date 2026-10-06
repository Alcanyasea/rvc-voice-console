# -*- coding: utf-8 -*-
"""麦克风音量检查/修复 + 实时峰值电平测量"""
import sys, time
import comtypes
from comtypes import CLSCTX_ALL, POINTER, cast
from pycaw.pycaw import (
    AudioUtilities, IAudioEndpointVolume, IAudioMeterInformation,
    IMMDeviceEnumerator, EDataFlow, DEVICE_STATE,
)

TARGET = "Misiom"

dev_enum = AudioUtilities.GetDeviceEnumerator().QueryInterface(IMMDeviceEnumerator)
coll = dev_enum.EnumAudioEndpoints(EDataFlow.eCapture.value, DEVICE_STATE.ACTIVE.value)
count = coll.GetCount()

target_dev = None
print("=== 激活的麦克风设备 ===")
for i in range(count):
    dev = coll.Item(i)
    obj = AudioUtilities.CreateDevice(dev)
    name = obj.FriendlyName
    ep = cast(dev.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None),
              POINTER(IAudioEndpointVolume))
    vol = round(ep.GetMasterVolumeLevelScalar() * 100)
    mute = bool(ep.GetMute())
    print(f"[{i}] {name}  音量={vol}%  静音={mute}")
    if TARGET in name:
        target_dev = dev

if target_dev is None:
    print("!! 没找到包含 '%s' 的麦克风" % TARGET)
    sys.exit(1)

ep = cast(target_dev.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None),
          POINTER(IAudioEndpointVolume))

# 修复：解除静音 + 音量拉满
ep.SetMute(0, None)
ep.SetMasterVolumeLevelScalar(1.0, None)
print("\n>>> 已设置: 静音=关, 音量=100%")

# 实时峰值测量 12 秒
meter = cast(target_dev.Activate(IAudioMeterInformation._iid_, CLSCTX_ALL, None),
             POINTER(IAudioMeterInformation))
print(">>> 现在请对着麦克风说话 12 秒...")
peaks = []
t0 = time.time()
while time.time() - t0 < 12:
    peaks.append(meter.GetPeakValue())
    time.sleep(0.05)
peak_max = max(peaks)
avg_speech = sorted(peaks)[-20:]  # 最高20个采样
avg20 = sum(avg_speech) / len(avg_speech)
print("\n=== 测量结果 ===")
print(f"12秒内最大峰值: {peak_max*100:.1f}%  ({20*__import__('math').log10(max(peak_max,1e-6)):.1f} dBFS)")
print(f"说话时平均峰值(前20高): {avg20*100:.1f}%  ({20*__import__('math').log10(max(avg20,1e-6)):.1f} dBFS)")
if peak_max > 0.95:
    print("结论: 峰值接近满格 -> 可能爆音，建议把音量降到 80%")
elif peak_max > 0.25:
    print("结论: 电平健康 (理想区间 25%~80%)")
elif peak_max > 0.05:
    print("结论: 电平偏低 -> 建议在系统中开启麦克风加强(+20dB) 或靠近麦克风说话")
else:
    print("结论: 几乎无声 -> 你刚才可能没说话，或麦克风通路有问题")
