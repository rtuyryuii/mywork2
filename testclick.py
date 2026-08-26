import os

import sys

import time

import subprocess

import pyautogui



# 强制 UTF-8 编码，防止控制台打印异常

sys.stdout.reconfigure(encoding='utf-8')

pyautogui.FAILSAFE = False



def log(msg):

    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)



def main():

    log("🚀 启动 Chrome 浏览器...")

    

    # 查找 Chrome 可执行文件路径

    chrome_path = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

    if not os.path.exists(chrome_path):

        chrome_path = r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"



    # 以最大化方式启动 Chrome 并打开注册页面

    subprocess.Popen([

        chrome_path,

        "--start-maximized",

        "--no-first-run",

        "--no-default-browser-check",

        "--disable-infobars",

        "https://signup.live.com/"

    ])



    log("⏳ 等待 15 秒加载登录页面...")

    time.sleep(15)



    log("🎯 移动鼠标并点击坐标 (371, 390)...")

    pyautogui.moveTo(371, 390, duration=0.5)

    pyautogui.click()

    time.sleep(1)



    log("⌨️ 正在输入文本: abcd1234@outlook.com")

    pyautogui.write("abcd1234@outlook.com", interval=0.08)

    time.sleep(3)



    log("📸 保存最终截图为 abcd1234.png...")

    pyautogui.screenshot().save("abcd1234.png")

    log("✅ 自动化测试完成！")



if __name__ == "__main__":

    main()
