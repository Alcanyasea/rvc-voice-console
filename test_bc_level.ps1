& "D:\voice change\RVC2026\RVC20260718Nvidia\runtime\python.exe" -c "
import time
import numpy as np
import sounddevice as sd

hostapis = sd.query_hostapis()
devices = sd.query_devices()

def find_wasapi_input(name_part):
    for i, d in enumerate(devices):
        if name_part in d['name'] and d['max_input_channels'] > 0 and hostapis[d['hostapi']]['name'] == 'Windows WASAPI':
            return i
    return None

idx = find_wasapi_input('NVIDIA Broadcast')
info = devices[idx]
sr = int(info['default_samplerate'])
print('Broadcast 麦克风 @%dHz，请持续说话5秒...' % sr)
frames = int(5.0 * sr)
rec = np.zeros((frames, 2), dtype='float32')
pos = [0]
def cb(ind, f, t, s):
    n = min(len(ind), len(rec) - pos[0])
    if n > 0:
        rec[pos[0]:pos[0]+n] = ind[:n]
        pos[0] += n
with sd.InputStream(device=idx, channels=2, samplerate=sr, dtype='float32', blocksize=sr//10, callback=cb):
    time.sleep(5)
mono = rec[:, 0]
r = float(np.sqrt(np.mean(mono**2)))
p = float(np.max(np.abs(mono)))
print('RMS=%.4f Peak=%.4f' % (r, p))
# 模拟 RVC 输入链: tanh(x*3)
sim = np.tanh(mono * 3.0)
sp = float(np.max(np.abs(sim)))
sat = float(np.mean(np.abs(mono) > 0.25)) * 100
print('进 RVC 后峰值(tanh*3): %.3f  超过0.25的样本占比: %.1f%%' % (sp, sat))
if p > 0.35 or sat > 15:
    print('结论: 输入电平偏热, x3 增益正在深度压限 -> 会产生电音/失真, 需要降增益')
else:
    print('结论: 电平正常, x3 增益不会明显失真')
" 2>&1