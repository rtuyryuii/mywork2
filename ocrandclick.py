import os
import sys
import time
import logging
from pathlib import Path
import pyautogui
from PIL import ImageDraw
from rapidocr_onnxruntime import RapidOCR

# 强制 UTF-8 编码，防止 Windows 控制台打印异常
sys.stdout.reconfigure(encoding='utf-8')
pyautogui.FAILSAFE = False

# 路径与日志设置
BASE_DIR = Path(__file__).resolve().parent
LOG_FILE = BASE_DIR / "ocrandclick.log"

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
    """内存直读识图等待逻辑"""
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


def start_maximized_chrome(url="https://signup.live.com/"):
    logger.info("🌐 启动 Chrome 浏览器 (窗口最大化)...")
    chrome_path = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
    if not os.path.exists(chrome_path):
        chrome_path = r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"

    flags = (
        '--start-maximized '
        '--no-first-run '
        '--no-default-browser-check '
        '--disable-save-password-bubble '
        '--disable-single-click-autofill '
        '--disable-popup-blocking '
        '--disable-infobars'
    )
    
    chrome_cmd = f'start "" "{chrome_path}" {flags} "{url}"'
    os.system(chrome_cmd)
    time.sleep(5)


def main():
    logger.info("================== 开始运行自动化识图与点击测试 ==================")

    try:
        # 1. 启动全屏 Chrome
        start_maximized_chrome("https://signup.live.com/")

        # 2. OCR 识图匹配
        wait_for_text_on_screen("Create your Microsoft account", max_retries=15)
        logger.info("🎉 识别结果: OCR 页面文本匹配成功！")

        # 3. 点击绝对中心坐标 (512, 384) 并写入
        click_x, click_y = 512, 384
        logger.info(f"🎯 移动鼠标并点击中心点坐标 ({click_x}, {click_y})...")
        pyautogui.moveTo(click_x, click_y, duration=0.5)
        pyautogui.click()
        time.sleep(1)

        logger.info("⌨️ 正在输入文本: abcd1234@outlook.com")
        pyautogui.write("abcd1234@outlook.com", interval=0.08)
        time.sleep(3)

        # 4. 捕获屏幕并在 (512, 384) 画红色十字/圆圈星标
        logger.info(f"📸 捕获屏幕并在 ({click_x}, {click_y}) 标注红星标记...")
        screenshot = pyautogui.screenshot()
        draw = ImageDraw.Draw(screenshot)

        r = 15
        # 画十字和中心红圈
        draw.line([(click_x - r, click_y), (click_x + r, click_y)], fill="red", width=2)
        draw.line([(click_x, click_y - r), (click_x, click_y + r)], fill="red", width=2)
        draw.ellipse([click_x - 5, click_y - 5, click_x + 5, click_y + 5], outline="red", width=2)

        screenshot.save("abcd1234.png")
        logger.info("✅ 自动化测试完成！图片 abcd1234.png 已生成（含 512x384 红星标记）。")

    except Exception as e:
        logger.error(f"❌ 运行遇到异常: {e}", exc_info=True)
        sys.exit(1)
    finally:
        logger.info("================== 任务运行结束 ==================")


if __name__ == "__main__":
    main()
