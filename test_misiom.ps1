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

midx = find_wasapi_input('Misiom-Gaming Center')
if midx is None:
    print('找不到 Misiom 麦克风')
else:
    d = devices[midx]
    print('录制: %s @%dHz (对你说话!)' % (d['name'], d['default_samplerate']))
    r, p = capture(midx)
    verdict = '有信号' if p > 0.002 else '静音'
    print('Misiom 原始麦克风: RMS=%.5f Peak=%.5f -> %s' % (r, p, verdict))
    print()
    print('判读: 有信号=物理麦正常,问题在Broadcast; 静音=物理麦就没进声卡(检查声卡上的麦克风静音键/旋钮、Windows录音电平)')
" 2>&1