# pythonw 无控制台启动器：重定向输出到日志后运行 realtime_gui.py
# 由 变声控制台 的"启动 RVC"按钮调用：runtime\pythonw.exe -I realtime_guiw.pyw
import os
import sys

RVC_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(RVC_DIR)
sys.path.insert(0, RVC_DIR)

log_path = os.path.join(RVC_DIR, "realtime_gui.log")
log = open(log_path, "w", encoding="utf-8", buffering=1)
sys.stdout = log
sys.stderr = log

# FSG 的错误弹窗依赖 __main__.__file__，runpy 方式下没有，补上防止二次崩溃
sys.modules["__main__"].__file__ = os.path.join(RVC_DIR, "realtime_gui.py")

import runpy

runpy.run_path(os.path.join(RVC_DIR, "realtime_gui.py"), run_name="__main__")
