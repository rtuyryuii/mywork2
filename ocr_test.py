import os
import sys
import time
import logging
import subprocess
from pathlib import Path
import pyautogui
from rapidocr_onnxruntime import RapidOCR

# 强制 UTF-8 编码，防止控制台及日志乱码
sys.stdout.reconfigure(encoding='utf-8')

# 基础设置
pyautogui.FAILSAFE = False

# 路径设置
BASE_DIR = Path(__file__).resolve().parent
LOG_FILE = BASE_DIR / "pyautogui_chrome_test.log"

# 初始化 OCR 识图引擎
ocr_engine = RapidOCR()

# 日志配置
logger = logging.getLogger("chrome_test")
logger.setLevel(logging.INFO)

formatter = logging.Formatter('%(asctime)s - [%(levelname)s] - %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

# 写入文件
file_handler = logging.FileHandler(LOG_FILE, mode='w', encoding='utf-8')
file_handler.setFormatter(formatter)
logger.addHandler(file_handler)

# 控制台输出
console_handler = logging.StreamHandler()
console_handler.setFormatter(formatter)
logger.addHandler(console_handler)


def wait_for_text_on_screen(target_text, max_retries=15):
    """内存直读识图等待关键字（无点击、无动作）"""
    logger.info(f"🔍 内存识图中，寻找页面关键字: [{target_text}]...")
    target_lower = target_text.lower()

    for attempt in range(1, max_retries + 1):
        frame_pil = pyautogui.screenshot()
        result, _ = ocr_engine(frame_pil)

        if result:
            for line in result:
                recognized_text = line[1]
                if target_lower in recognized_text.lower():
                    logger.info(f"✅ 第 {attempt} 次识图成功，匹配到关键字: [{recognized_text}]")
                    return True

        logger.info(f"⏳ 第 {attempt}/{max_retries} 次未匹配到 [{target_text}]，等待重试...")
        time.sleep(1.5)

    logger.error(f"❌ 页面文本匹配超时未能识别: [{target_text}]")
    raise TimeoutError(f"Timeout waiting for text on screen: {target_text}")


def start_new_chrome(url="https://signup.live.com/"):
    logger.info("🌐 启动 Chrome 浏览器...")
    chrome_path = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
    if not os.path.exists(chrome_path):
        chrome_path = r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"

    subprocess.Popen([
        chrome_path,
        "--start-maximized",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-infobars",
        url
    ])


def main():
    logger.info("================== 开始运行纯识图匹配测试 ==================")

    try:
        # 1. 启动浏览器
        start_new_chrome("https://signup.live.com/")

        # 2. 纯文本识图匹配测试（不进行任何点击/输入）
        wait_for_text_on_screen("Create your Microsoft account", max_retries=15)

        logger.info("🎉 OCR 匹配测试通过！日志已记录。")

    except Exception as e:
        logger.error(f"❌ 运行过程中遇到异常: {e}", exc_info=True)
        sys.exit(1)
    finally:
        logger.info("================== 任务运行结束 ==================")


if __name__ == "__main__":
    main()
