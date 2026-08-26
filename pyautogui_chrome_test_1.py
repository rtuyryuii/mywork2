import os
import sys
import time
import random
import logging
import threading
import subprocess
from pathlib import Path
import pyautogui
from PIL import ImageDraw
from rapidocr_onnxruntime import RapidOCR

# ==================== 基本配置 ====================
sys.stdout.reconfigure(encoding='utf-8')
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - [%(levelname)s] - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("pyautogui_chrome_test.log", mode='w', encoding='utf-8')
    ]
)
logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).parent.resolve()

# 关键修改：文件名改为 account.txt
ACCOUNT_FILE = BASE_DIR / "account.txt"
SCROT_PNG_DIR = BASE_DIR / "scrot_png"
SCROT_PNG_DIR.mkdir(exist_ok=True)

ENABLE_DEBUG_SCREENSHOT_THREAD = True
stop_screenshot_thread = False

pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0.1

# 初始化 OCR 引擎
ocr_engine = RapidOCR()


# ==================== 0. 辅助函数 ====================
def random_delay(min_sec=1.0, max_sec=3.0):
    time.sleep(random.uniform(min_sec, max_sec))


def wait_for_text_on_screen(target_text, max_retries=15):
    """内存直读识图"""
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
        random_delay(1.0, 3.0)

    logger.error(f"❌ 页面文本匹配超时未能识别: [{target_text}]")
    raise TimeoutError(f"Timeout waiting for text on screen: {target_text}")

# ==================== 1. 后台截图线程 (带红色十字准星) ====================
def screenshot_worker(interval=1.0):
    count = 1
    logger.info("📸 [THREAD] 启动后台截图线程...")
    while not stop_screenshot_thread:
        try:
            img = pyautogui.screenshot()
            mx, my = pyautogui.position()

            draw = ImageDraw.Draw(img)
            r = 8
            draw.line([(mx - r, my), (mx + r, my)], fill="red", width=2)
            draw.line([(mx, my - r), (mx, my + r)], fill="red", width=2)
            draw.ellipse([mx - 3, my - 3, mx + 3, my + 3], outline="red", width=2)

            timestamp = time.strftime("%Y%m%d_%H%M%S")
            filename = SCROT_PNG_DIR / f"shot_{timestamp}_{count:04d}.png"
            img.save(filename)
            count += 1
        except Exception as e:
            logger.error(f"⚠️ [THREAD] 截图异常: {e}")
        time.sleep(interval)


# ==================== 2. 从老脚本移植的原生写入机制 ====================
def read_account_line(lineno=1):
    """读取 account.txt 文件的指定行"""
    if not ACCOUNT_FILE.exists():
        raise FileNotFoundError(f"未找到账户配置文件: {ACCOUNT_FILE}")
    with open(ACCOUNT_FILE, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    if lineno <= 0 or lineno > len(lines):
        raise IndexError(f"读取行号 {lineno} 越界 (文件共 {len(lines)} 行)")
    return lines[lineno - 1]


# ==================== 3. 主流程测试 ====================
def main1():
    global stop_screenshot_thread
    logger.info("================== 开始运行纯坐标老脚本写入测试 ==================")
    
    # 启动后台截图
    scrot_thread = None
    if ENABLE_DEBUG_SCREENSHOT_THREAD:
        scrot_thread = threading.Thread(target=screenshot_worker, args=(1.0,), daemon=True)
        scrot_thread.start()

    try:
        # Step 1: 启动 Chrome 浏览器
        logger.info("🚀 启动 Chrome 浏览器...")
        chrome_path = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
        if not os.path.exists(chrome_path):
            chrome_path = r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"

        subprocess.Popen([
            chrome_path,
            "--start-maximized",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-infobars",
            "https://signup.live.com/"
        ])

        # Step 2: OCR 识别文本等待页面加载
        wait_for_text_on_screen("Create your Microsoft account", max_retries=15)

        # Step 3: 点击坐标获得 Focus
        logger.info("🎯 移动鼠标并点击坐标 (371, 390)...")
        pyautogui.moveTo(371, 390, duration=0.5)
        pyautogui.click()
        time.sleep(1)

        # Step 4: 读取 account.txt 第 1 行文本并写入
        text_line1 = read_account_line(1)
        logger.info(f"⌨️ 正在输入文本: {text_line1}")
        pyautogui.write(text_line1, interval=0.08)
        time.sleep(3)

        # Step 5: 留屏供后台线程截图捕获
        logger.info("📸 写入完毕，留屏 5 秒供截图线程捕获最终渲染图...")
        time.sleep(5)
        logger.info("🎉 测试成功完成！请去 scrot_png 查看输出图片。")

    except Exception as e:
        logger.error(f"💥 运行遇到异常: {e}", exc_info=True)
        sys.exit(1)
    finally:
        if ENABLE_DEBUG_SCREENSHOT_THREAD and scrot_thread:
            stop_screenshot_thread = True
            scrot_thread.join(timeout=3)
            logger.info("🛠️ [DEBUG] 后台截图线程退出。")

if __name__ == "__main__":
    main1()
