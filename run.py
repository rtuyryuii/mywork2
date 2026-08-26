import os
import sys
import json
import zipfile
import urllib.request
import subprocess
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(__file__).resolve().parent
SCROT_PNG_DIR = BASE_DIR / "scrot_png"
ZIP_FILE = BASE_DIR / "scrot_png.zip"

# 关键修改：文件名改为 account.txt
ACCOUNT_FILE = BASE_DIR / "account.txt"
LOG_FILE = BASE_DIR / "pyautogui_chrome_test.log"

IANA_TO_WINDOWS_TZ = {
    "America/New_York": "Eastern Standard Time",
    "America/Detroit": "Eastern Standard Time",
    "America/Chicago": "Central Standard Time",
    "America/Los_Angeles": "Pacific Standard Time",
    "Asia/Shanghai": "China Standard Time"
}

def run_cmd(cmd, shell=True):
    result = subprocess.run(
        cmd, shell=shell, text=True, capture_output=True, encoding='utf-8', errors='ignore'
    )
    if result.stdout and result.stdout.strip():
        print(result.stdout.strip(), flush=True)
    if result.stderr and result.stderr.strip():
        print(f"[STDERR] {result.stderr.strip()}", flush=True)
    return result.returncode

def prepare_directories():
    SCROT_PNG_DIR.mkdir(parents=True, exist_ok=True)

def fetch_dynamic_timezone():
    url = "https://ipinfo.io"
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'curl/7.68.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode('utf-8'))
            iana_tz = data.get("timezone", "America/New_York")
            return IANA_TO_WINDOWS_TZ.get(iana_tz, "Eastern Standard Time")
    except Exception as e:
        print(f"❌ 获取 IP 时区失败: {e}，默认使用 Eastern Standard Time", flush=True)
        return "Eastern Standard Time"

def check_account_file():
    if not ACCOUNT_FILE.exists():
        print(f"❌ [ERROR] {ACCOUNT_FILE.name} 文件不存在！", flush=True)
        return False
    
    with open(ACCOUNT_FILE, 'r', encoding='utf-8', errors='ignore') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    
    if len(lines) < 3:
        print(f"❌ [ERROR] {ACCOUNT_FILE.name} 文件行数不足（当前 {len(lines)} 行，预期至少 3 行）", flush=True)
        return False

    print(f"✅ {ACCOUNT_FILE.name} 文件校验通过！本次待填入账号: {lines[0]}", flush=True)
    return True

def zip_screenshots():
    if not SCROT_PNG_DIR.exists():
        print("⚠️ scrot_png 目录不存在，跳过打包", flush=True)
        return

    print("📦 [ZIP] 开始打包 scrot_png 截图目录...", flush=True)
    with zipfile.ZipFile(ZIP_FILE, 'w', zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(SCROT_PNG_DIR):
            for file in files:
                file_path = Path(root) / file
                arcname = file_path.relative_to(BASE_DIR)
                zf.write(file_path, arcname)
    print(f"✅ 截图成功打包至: {ZIP_FILE}", flush=True)

def commit_and_push_artifacts():
    print("\n================ [收尾] 开始提交 account.txt / log / zip 产物入库 ================", flush=True)
    
    zip_screenshots()

    run_cmd('git config user.name "github-actions[bot]"')
    run_cmd('git config user.email "github-actions[bot]@users.noreply.github.com"')

    if ACCOUNT_FILE.exists():
        run_cmd(f'git add -f "{ACCOUNT_FILE.name}"')
        print(f"➕ 已添加: {ACCOUNT_FILE.name}", flush=True)
    
    if LOG_FILE.exists():
        run_cmd(f'git add -f "{LOG_FILE.name}"')
        print(f"➕ 已添加: {LOG_FILE.name}", flush=True)

    if ZIP_FILE.exists():
        run_cmd(f'git add -f "{ZIP_FILE.name}"')
        print(f"➕ 已添加: {ZIP_FILE.name}", flush=True)

    commit_code = run_cmd('git commit -m "chore(ci): save account.txt, pyautogui log and scrot_png.zip [skip ci]"')
    if commit_code == 0:
        print("🚀 正在推送到远程 main 分支...", flush=True)
        push_code = run_cmd('git push origin main')
        if push_code == 0:
            print("🎉 所有产物成功写入并推送到 Git 仓库！", flush=True)
        else:
            print("❌ git push 失败，请检查仓库写入权限或是否有冲突！", flush=True)
    else:
        print("ℹ️ Git 认为无变更或已是最新状态。", flush=True)

def main():
    print("================ [1/5] 整理项目目录结构 ================", flush=True)
    prepare_directories()

    print("\n================ [2/5] 动态设置 Windows 系统时区 ================", flush=True)
    target_win_tz = fetch_dynamic_timezone()
    run_cmd(f'tzutil /s "{target_win_tz}"')

    print("\n================ [3/5] 执行 account.sh 生成新账号 ================", flush=True)
    bash_path = r"C:\Program Files\Git\bin\bash.exe"
    if run_cmd(f'"{bash_path}" ./account.sh') != 0:
        print("❌ 生成账号脚本执行失败！", flush=True)
        sys.exit(1)

    if not check_account_file():
        sys.exit(1)

    print("\n================ [4/5] 检查并安装 OCR 工具库 ================", flush=True)
    run_cmd(f'"{sys.executable}" -m pip install rapidocr_onnxruntime --quiet')

    print("\n================ [5/5] 执行 PyAutoGUI 主逻辑 ================", flush=True)
    code = run_cmd(f'"{sys.executable}" pyautogui_chrome_test.py')
    
    if code == 0:
        print("✅ PyAutoGUI 脚本执行完毕 (无异常退出)", flush=True)
    else:
        print(f"⚠️ PyAutoGUI 脚本执行失败，退出码: {code}，请查阅 pyautogui_chrome_test.log 文件！", flush=True)

    commit_and_push_artifacts()
    sys.exit(0)

if __name__ == "__main__":
    main()
