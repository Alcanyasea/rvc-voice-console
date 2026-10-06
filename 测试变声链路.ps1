& "D:\voice change\RVC2026\RVC20260718Nvidia\runtime\python.exe" -c "
import time
import numpy as np
import sounddevice as sd

hostapis = sd.query_hostapis()
devices = sd.query_devices()

def find_wasapi_input(name_part):
    for i, d in enumerate(devices):
        ha = hostapis[d['hostapi']]['name']
        if name_part in d['name'] and d['max_input_channels'] > 0 and ha == 'Windows WASAPI':
            return i
    return None

def capture(idx, dur=5.0):
    info = devices[idx]
    sr = int(info['default_samplerate'])
    ch = min(2, int(info['max_input_channels']))
    frames = int(dur * sr)
    rec = np.zeros((frames, ch), dtype='float32')
    pos = [0]
    def cb(ind, f, t, s):
        n = min(len(ind), len(rec) - pos[0])
        if n > 0:
            rec[pos[0]:pos[0]+n] = ind[:n]
            pos[0] += n
    with sd.InputStream(device=idx, channels=ch, samplerate=sr, dtype='float32', blocksize=sr//10, callback=cb):
        time.sleep(dur)
    mono = rec[:, 0]
    return float(np.sqrt(np.mean(mono**2))), float(np.max(np.abs(mono)))

def report(label, rms, peak):
    verdict = '有信号' if peak > 0.002 else '静音'
    print('%s: RMS=%.5f Peak=%.5f -> %s' % (label, rms, peak, verdict))

bidx = find_wasapi_input('NVIDIA Broadcast')
if bidx is None:
    print('找不到 Broadcast 麦克风')
else:
    print('录制上游: %s (对你说话!)' % devices[bidx]['name'])
    r, p = capture(bidx)
    report('上游 Broadcast麦克风', r, p)

didx = find_wasapi_input('CABLE Output')
print('录制下游: %s' % devices[didx]['name'])
r, p = capture(didx)
report('下游 CABLE变声输出', r, p)

print()
print('判读: 两端有信号=链路OK(去查游戏麦克风设置); 上游静音=Broadcast没收到你说话; 上游有下游静音=RVC转换断流')
" 2>&1