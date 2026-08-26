import os
import sys
import time
import math
import random
import logging
import threading
import pyautogui
import pyperclip
from pathlib import Path
from rapidocr_onnxruntime import RapidOCR

# 设置编码
sys.stdout.reconfigure(encoding='utf-8')

# PyAutoGUI 基础设置
pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0.1

# 路径设置
BASE_DIR = Path(__file__).resolve().parent
SCROT_PNG_DIR = BASE_DIR / "scrot_png"
ACCOUNT_FILE = BASE_DIR / "account.txt"
LOG_FILE = BASE_DIR / "pyautogui_chrome_test.log"

# 确保目录存在
SCROT_PNG_DIR.mkdir(parents=True, exist_ok=True)

# 初始化 OCR 识图引擎（内存直读）
ocr_engine = RapidOCR()

# 全局调试开关（测试阶段设为 True，生产阶段设为 False）
ENABLE_DEBUG_SCREENSHOT_THREAD = True

# 日志配置
logger = logging.getLogger("chrome_test")
logger.setLevel(logging.INFO)

formatter = logging.Formatter('%(asctime)s - [%(levelname)s] - %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

file_handler = logging.FileHandler(LOG_FILE, mode='w', encoding='utf-8')
file_handler.setFormatter(formatter)
file_handler.setLevel(logging.INFO)
logger.addHandler(file_handler)

console_handler = logging.StreamHandler()
console_handler.setFormatter(formatter)
console_handler.setLevel(logging.INFO)
logger.addHandler(console_handler)

stop_screenshot_thread = False

def human_move_to(target_x, target_y, steps=25):
    """拟人化贝塞尔曲线鼠标移动"""
    start_x, start_y = pyautogui.position()
    
    if math.hypot(target_x - start_x, target_y - start_y) < 5:
        pyautogui.moveTo(target_x, target_y)
        return

    control_x = (start_x + target_x) / 2 + random.randint(-100, 100)
    control_y = (start_y + target_y) / 2 + random.randint(-100, 100)

    for i in range(1, steps + 1):
        t = i / steps
        curve_x = (1 - t)**2 * start_x + 2 * (1 - t) * t * control_x + t**2 * target_x
        curve_y = (1 - t)**2 * start_y + 2 * (1 - t) * t * control_y + t**2 * target_y
        
        jitter_x = random.uniform(-1.0, 1.0) if i < steps else 0
        jitter_y = random.uniform(-1.0, 1.0) if i < steps else 0

        pyautogui.moveTo(curve_x + jitter_x, curve_y + jitter_y)
        
        sleep_time = random.uniform(0.005, 0.015)
        if t < 0.2 or t > 0.8:
            sleep_time += random.uniform(0.005, 0.01)
        time.sleep(sleep_time)

    pyautogui.moveTo(target_x, target_y)

def perform_click(target_x, target_y):
    """拟人移动并点击，增加输入框聚焦缓冲时间"""
    current_x, current_y = pyautogui.position()
    logger.info(f"🖱️ 拟人化移动鼠标: ({current_x}, {current_y}) -> ({target_x}, {target_y}) 并点击")
    
    human_move_to(target_x, target_y)
    time.sleep(random.uniform(0.1, 0.3))
    pyautogui.click()
    time.sleep(0.5)  # 增加延迟以确保输入框彻底获取焦点
    random_delay(0.5, 1.0)

def screenshot_worker(interval=1.0):
    """测试用后台独立截图写盘线程"""
    count = 1
    logger.info("📸 [THREAD] 启动测试用后台截图线程...")
    while not stop_screenshot_thread:
        try:
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            filename = SCROT_PNG_DIR / f"shot_{timestamp}_{count:04d}.png"
            pyautogui.screenshot().save(filename)
            count += 1
        except Exception as e:
            logger.error(f"⚠️ [THREAD] 截图线程异常: {e}")
        time.sleep(interval)
    logger.info("📸 [THREAD] 后台截图线程已停止。")

def random_delay(min_seconds=1.0, max_seconds=3.0):
    time.sleep(random.uniform(min_seconds, max_seconds))

def read_account_line(lineno=1):
    """读取 account.txt 文件的指定行"""
    if not ACCOUNT_FILE.exists():
        raise FileNotFoundError(f"未找到账户配置文件: {ACCOUNT_FILE}")
    with open(ACCOUNT_FILE, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    if lineno <= 0 or lineno > len(lines):
        raise IndexError(f"读取行号 {lineno} 越界 (文件共 {len(lines)} 行)")
    return lines[lineno - 1]

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

def start_new_chrome(url="about:blank"):
    logger.info("📍 [预设坐标] 将鼠标移动至初始捕捉点 (577, 345)...")
    human_move_to(577, 345)
    time.sleep(0.5)

    logger.info("🌐 启动 Chrome 浏览器 (已添加禁用密码保存提示参数)...")
    chrome_profile = BASE_DIR / "chrome_profile"
    
    flags = (
        '--window-size=1040,736 '
        '--no-first-run '
        '--no-default-browser-check '
        '--disable-save-password-bubble '
        '--disable-single-click-autofill '
        '--disable-autofill-keyboard-accessory-view '
        '--disable-offer-store-unmasked-wallet-cards '
        '--disable-popup-blocking '
        '--password-store=basic '
    )
    
    chrome_cmd = f'start chrome {flags} --user-data-dir="{chrome_profile}" "{url}"'
    os.system(chrome_cmd)
    random_delay(5, 8)

def main1():
    global stop_screenshot_thread
    logger.info("================== 开始运行无弹窗纯内存识字自动化注册 ==================")
    
    scrot_thread = None
    if ENABLE_DEBUG_SCREENSHOT_THREAD:
        logger.info("🛠️ [DEBUG] 启动后台截图写盘线程...")
        scrot_thread = threading.Thread(target=screenshot_worker, args=(1.0,), daemon=True)
        scrot_thread.start()

    try:
        start_new_chrome(url="https://signup.live.com")

        # ---------------- 阶段 1: 输入 Email ----------------
        wait_for_text_on_screen("Create your Microsoft account", max_retries=15)
        
        logger.info("👉 点击 Email 输入框 (371, 390)")
        perform_click(371, 390)

        text_line1 = read_account_line(1)
        logger.info(f"⌨️ 正在输入文本: {text_line1}")
        pyautogui.write(text_line1, interval=0.08)
        time.sleep(3)

        logger.info("👉 点击 Next 按钮 (362, 464)")
        perform_click(362, 464)

        # ---------------- 阶段 2: 输入 Password ----------------
        wait_for_text_on_screen("Create your password", max_retries=15)

        logger.info("👉 点击 Password 输入框 (372, 435)")
        perform_click(372, 435)

        # Step 4: 读取 account.txt 第 2 行文本并写入
        text_line2 = read_account_line(2)
        logger.info(f"⌨️ 正在输入文本: {text_line2}")
        pyautogui.write(text_line2, interval=0.08)
        time.sleep(3)

        logger.info("👉 点击 Next 按钮 (359, 539)")
        perform_click(359, 539)

        # ---------------- 阶段 3: 填写基本信息 ----------------
        wait_for_text_on_screen("Add some details", max_retries=15)

        logger.info("👉 点击 Month 下拉框 (351, 464)")
        perform_click(351, 464)
        pyautogui.press('down')
        pyautogui.press('enter')
        random_delay(1, 2)

        logger.info("👉 点击 Day 下拉框 (471, 464)")
        perform_click(471, 464)
        pyautogui.press('down')
        pyautogui.press('enter')
        random_delay(1, 2)

        logger.info("👉 点击 Year 输入框 (602, 464)")
        perform_click(602, 464)
        
        # Step 4: 读取 account.txt 第 3 行文本并写入
        text_line3 = read_account_line(3)
        logger.info(f"⌨️ 正在输入文本: {text_line3}")
        pyautogui.write(text_line3, interval=0.08)
        time.sleep(3)

        logger.info("👉 点击 Next 按钮 (351, 639)")
        perform_click(351, 639)

        logger.info("⏳ 步骤已顺利执行完毕！留存画面 15 秒...")
        time.sleep(15)
        logger.info("🎉 自动化流程全部圆满完成！")

    except Exception as e:
        logger.error(f"❌ 运行遇到致命异常: {e}", exc_info=True)
        sys.exit(1)
    finally:
        if ENABLE_DEBUG_SCREENSHOT_THREAD and scrot_thread:
            stop_screenshot_thread = True
            scrot_thread.join(timeout=3)
            logger.info("🛠️ [DEBUG] 后台截图线程退出。")
        logger.info("================== 任务运行结束 ==================")

if __name__ == "__main__":
    main1()
