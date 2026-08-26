import os
import sys
import time
import logging
import subprocess
from pathlib import Path
import pyautogui
from rapidocr_onnxruntime import RapidOCR

# 设置编码
sys.stdout.reconfigure(encoding='utf-8')

# PyAutoGUI 基础设置
pyautogui.FAILSAFE = False

# 路径设置
BASE_DIR = Path(__file__).resolve().parent
LOG_FILE = BASE_DIR / "ocr.log"

# 初始化 OCR 识图引擎（内存直读）
ocr_engine = RapidOCR()

# 日志配置
logger = logging.getLogger("ocr_test")
logger.setLevel(logging.INFO)

formatter = logging.Formatter('%(asctime)s - [%(levelname)s] - %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

file_handler = logging.FileHandler(LOG_FILE, mode='w', encoding='utf-8')
file_handler.setFormatter(formatter)
logger.addHandler(file_handler)

console_handler = logging.StreamHandler()
console_handler.setFormatter(formatter)
logger.addHandler(console_handler)


def wait_for_text_on_screen(target_text, max_retries=15):
    """原版内存直读识图逻辑"""
    logger.info(f"🔍 内存识图中，寻找页面关键字: [{target_text}] (最大重试 {max_retries} 次)...")
    target_lower = target_text.lower()

    for attempt in range(1, max_retries + 1):
        frame_pil = pyautogui.screenshot()
        result, _ = ocr_engine(frame_pil)

        if result:
            for line in result:
                recognized_text = line[1]
                if target_lower in recognized_text.lower():
                    logger.info(f"✅ 第 {attempt} 次识图成功，匹配关键字: [{recognized_text}]")
                    return True

        logger.info(f"⏳ 第 {attempt}/{max_retries} 次未匹配到 [{target_text}]，等待重试...")
        time.sleep(2.0)

    logger.error(f"❌ 页面文本匹配超时未能识别: [{target_text}]")
    raise TimeoutError(f"Timeout waiting for text on screen: {target_text}")


def start_new_chrome(url="https://signup.live.com"):
    logger.info("🌐 启动 Chrome 浏览器...")
    chrome_profile = BASE_DIR / "chrome_profile"
    
    flags = (
        '--window-size=1040,736 '
        '--no-first-run '
        '--no-default-browser-check '
        '--disable-save-password-bubble '
        '--disable-single-click-autofill '
        '--disable-popup-blocking '
    )
    
    chrome_cmd = f'start chrome {flags} --user-data-dir="{chrome_profile}" "{url}"'
    os.system(chrome_cmd)
    time.sleep(5)


def main():
    logger.info("================== 开始运行纯内存识字测试 ==================")

    try:
        # 1. 启动浏览器
        start_new_chrome("https://signup.live.com")

        # 2. OCR 识图匹配检测
        wait_for_text_on_screen("Create your Microsoft account", max_retries=15)

        logger.info("🎉 识别结果: OCR 页面文本匹配成功！")

    except Exception as e:
        logger.error(f"❌ 运行遇到异常: {e}", exc_info=True)
        sys.exit(1)
    finally:
        logger.info("================== 任务运行结束 ==================")


if __name__ == "__main__":
    main()
