# ============================================================
#  ChatBI 一键停止脚本（Windows / PowerShell）
#  作用：停止 4 个 MCP 服务 + FastAPI 接口（不停止 PostgreSQL，避免误关数据库）
#  用法：powershell -ExecutionPolicy Bypass -File stop_all.ps1
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "正在停止 ChatBI 相关进程 ..." -ForegroundColor Yellow

# 目标脚本文件名（用脚本名精确匹配，避免误杀其它 Python 进程）
$targets = @(
    "statistic_db_mcp_tools.py",
    "python_chart_mcp.py",
    "machine_learning_mcp.py",
    "ywfl_mcp.py",
    "chat_api.py"
)

$stopped = 0
foreach ($t in $targets) {
    # 通过命令行参数匹配包含该脚本名的 python 进程
    $procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
             Where-Object { $_.CommandLine -like "*$t*" }
    foreach ($p in $procs) {
        Stop-Process -Id $p.ProcessId -Force
        Write-Host "  已停止 PID=$($p.ProcessId)  ($t)" -ForegroundColor Green
        $stopped++
    }
}

if ($stopped -eq 0) {
    Write-Host "  没有找到正在运行的 ChatBI 进程。" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "停止完成。PostgreSQL 未停止（如需停止请手动执行 pg_ctl stop）。" -ForegroundColor Yellow
Write-Host ""
