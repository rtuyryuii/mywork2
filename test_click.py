import os
import sys
import time
import logging
import subprocess
import pyautogui
from pathlib import Path
from rapidocr_onnxruntime import RapidOCR

# 强制 UTF-8 编码，防止 GitHub Actions 日志乱码
sys.stdout.reconfigure(encoding='utf-8')

pyautogui.FAILSAFE = False

BASE_DIR = Path(__file__).resolve().parent
LOG_FILE = BASE_DIR / "test_click.log"

ocr_engine = RapidOCR()

logger = logging.getLogger("chrome_test")
logger.setLevel(logging.INFO)

formatter = logging.Formatter('%(asctime)s - [%(levelname)s] - %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

file_handler = logging.FileHandler(LOG_FILE, mode='w', encoding='utf-8')
file_handler.setFormatter(formatter)
logger.addHandler(file_handler)

console_handler = logging.StreamHandler()
console_handler.setFormatter(formatter)
logger.addHandler(console_handler)


def wait_for_text_on_screen(target_text, max_retries=15):
    """内存直读识图等待关键字"""
    logger.info(f"🔍 内存识图中，寻找页面关键字: [{target_text}]...")
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
        time.sleep(1.5)

    logger.error(f"❌ 页面文本匹配超时未能识别: [{target_text}]")
    raise TimeoutError(f"Timeout waiting for text on screen: {target_text}")


def start_new_chrome(url="https://signup.live.com/"):
    logger.info("🌐 以全屏方式启动 Chrome 浏览器...")
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
    logger.info("================== 开始运行 GitHub Actions 测试脚本 ==================")

    try:
        start_new_chrome("https://signup.live.com/")

        # 1. OCR 匹配等待页面加载
        wait_for_text_on_screen("Create your Microsoft account", max_retries=15)

        # 2. 移动并点击输入框（完全还原 testclick 的平滑/精准定位）
        logger.info("🎯 点击 Email 输入框坐标 (371, 390)...")
        pyautogui.moveTo(371, 390, duration=0.5)
        pyautogui.click()
        time.sleep(1)

        # 3. 写入目标字符串
        target_email = "xyz789@outlook.com"
        logger.info(f"⌨️ 正在写入字符串: {target_email}")
        pyautogui.write(target_email, interval=0.08)
        time.sleep(2)

        # 4. 点击 Next 按钮 (362, 464)
        logger.info("🎯 点击 Next 按钮坐标 (362, 464)...")
        pyautogui.moveTo(362, 464, duration=0.5)
        pyautogui.click()
        time.sleep(3)

        # 5. 保存结果截图
        result_png = BASE_DIR / "xyz789.png"
        logger.info(f"📸 正在保存运行结果截图至: {result_png}")
        pyautogui.screenshot().save(result_png)

        logger.info("🎉 脚本执行完毕！")

    except Exception as e:
        logger.error(f"❌ 运行过程中遇到异常: {e}", exc_info=True)
        pyautogui.screenshot().save(BASE_DIR / "xyz789.png")
        sys.exit(1)


if __name__ == "__main__":
    main()
