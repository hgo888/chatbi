# ============================================================
#  ChatBI 一键启动脚本（Windows / PowerShell）
#  作用：依次拉起 PostgreSQL -> 4 个 MCP 服务 -> FastAPI 接口
#  用法：在项目根目录右键「使用 PowerShell 运行」，或：
#        powershell -ExecutionPolicy Bypass -File start_all.ps1
# ============================================================

$ErrorActionPreference = "Stop"

# ---------- 0.0 清理重复的代理环境变量 ----------
# 系统中若同时存在 http_proxy / HTTP_PROXY / https_proxy / HTTPS_PROXY，
# 会导致 PowerShell 的 Env: 字典冲突，使 Start-Process 报"已添加相同键的项"。
Remove-Item Env:http_proxy   -ErrorAction SilentlyContinue
Remove-Item Env:HTTP_PROXY   -ErrorAction SilentlyContinue
Remove-Item Env:https_proxy  -ErrorAction SilentlyContinue
Remove-Item Env:HTTPS_PROXY  -ErrorAction SilentlyContinue

# ---------- 0. 基础路径 ----------
$ROOT      = $PSScriptRoot                          # 本脚本所在目录（smart_data_analysis_assistant）
$LANG_AGENT = Split-Path -Parent $ROOT              # 上一级目录（langGraph_agent）
$VENV      = Split-Path -Parent $LANG_AGENT         # 上两级目录（资料，.venv 所在位置）
$VENV_PY   = Join-Path $VENV ".venv\Scripts\python.exe"
$PG_BIN    = "C:\Program Files\PostgreSQL\16\bin"
$PGDATA    = "C:\Program Files\PostgreSQL\16\data"
$MCP_DIR   = Join-Path $ROOT "mcp_server"
$CHAT_DIR  = Join-Path $ROOT "chatbi_graph"

# ---------- 0.1 检查 venv ----------
if (-not (Test-Path $VENV_PY)) {
    Write-Host "[错误] 找不到虚拟环境 Python：$VENV_PY" -ForegroundColor Red
    Write-Host "请确认 .venv 目录存在（位于 $VENV）" -ForegroundColor Red
    exit 1
}

# ---------- 0.2 日志目录 ----------
$LOG_DIR = Join-Path $ROOT "logs"
if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR | Out-Null }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ChatBI 数据分析智能助手 —— 一键启动" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Python : $VENV_PY"
Write-Host "  MCP目录: $MCP_DIR"
Write-Host "  日志目录: $LOG_DIR"
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ---------- 1. 启动 PostgreSQL ----------
Write-Host "[1/6] 检查 PostgreSQL ..." -ForegroundColor Yellow
$pgRunning = $false
try {
    $conn = New-Object System.Net.Sockets.TcpClient
    $conn.Connect("127.0.0.1", 5432)
    $pgRunning = $true
    $conn.Close()
} catch { $pgRunning = $false }

if ($pgRunning) {
    Write-Host "      PostgreSQL 已在运行（端口 5432），跳过启动。" -ForegroundColor Green
} else {
    Write-Host "      PostgreSQL 未运行，正在启动 ..." -ForegroundColor Yellow
    $pgCtl = Join-Path $PG_BIN "pg_ctl.exe"
    if (-not (Test-Path $pgCtl)) {
        Write-Host "[错误] 找不到 pg_ctl.exe：$pgCtl" -ForegroundColor Red
        Write-Host "      请确认已安装 PostgreSQL 16（标准路径 C:\Program Files\PostgreSQL\16）" -ForegroundColor Red
        exit 1
    }
    # 用 pg_ctl 启动（-w 等待就绪）
    & $pgCtl -D $PGDATA -l (Join-Path $LOG_DIR "postgresql.log") -w start
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] PostgreSQL 启动失败，详见日志。" -ForegroundColor Red
        exit 1
    }
    Write-Host "      PostgreSQL 启动成功。" -ForegroundColor Green
}

# ---------- 2. 启动 4 个 MCP 服务 ----------
$mcpServices = @(
    @{ Name = "search_db_mcp";        File = "statistic_db_mcp_tools.py"; Port = 9004 }
    @{ Name = "python_chart_mcp";     File = "python_chart_mcp.py";      Port = 9002 }
    @{ Name = "machine_learning_mcp"; File = "machine_learning_mcp.py";  Port = 9003 }
    @{ Name = "ywfl_mcp";             File = "ywfl_mcp.py";              Port = 9005 }
)

# 通用启动函数：用 cmd /c start 让子进程脱离当前 PowerShell 进程树，
# 这样脚本退出后服务仍能持续运行。
function Start-ChatBIService {
    param(
        [string]$PyFile,
        [string]$WorkDir,
        [string]$OutLog,
        [string]$ErrLog,
        [string]$Name
    )
    # 用 cmd /c start /b 启动，让子进程脱离当前 PowerShell 进程树，
    # 这样脚本退出后服务仍能持续运行。
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c start /b `"`" `"$VENV_PY`" `"$PyFile`" > `"$OutLog`" 2> `"$ErrLog`""
    $psi.WorkingDirectory = $WorkDir
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    Write-Host "      $Name 已启动（PID=$($p.Id)），日志见 $OutLog" -ForegroundColor Green
}

$i = 1
foreach ($svc in $mcpServices) {
    $i++
    $label = "[$i/6]"
    Write-Host "$label 启动 MCP 服务：$($svc.Name)（端口 $($svc.Port)）..." -ForegroundColor Yellow
    $pyFile = Join-Path $MCP_DIR $svc.File
    $outLog = Join-Path $LOG_DIR "$($svc.Name).out.log"
    $errLog = Join-Path $LOG_DIR "$($svc.Name).err.log"
    Start-ChatBIService -PyFile $pyFile -WorkDir $MCP_DIR -OutLog $outLog -ErrLog $errLog -Name $svc.Name
}

# ---------- 3. 启动 FastAPI 接口 ----------
Write-Host "[6/6] 启动 FastAPI 接口（端口 9008）..." -ForegroundColor Yellow
$chatApi = Join-Path $CHAT_DIR "chat_api.py"
$apiOut  = Join-Path $LOG_DIR "chat_api.out.log"
$apiErr  = Join-Path $LOG_DIR "chat_api.err.log"
Start-ChatBIService -PyFile $chatApi -WorkDir $CHAT_DIR -OutLog $apiOut -ErrLog $apiErr -Name "chat_api"

# ---------- 4. 等待 + 状态汇总 ----------
Write-Host ""
Write-Host "等待 3 秒让各服务完成监听 ..." -ForegroundColor DarkGray
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  启动完成！服务清单："
Write-Host "============================================================" -ForegroundColor Cyan

$ports = @(
    @{ Name = "PostgreSQL";           Port = 5432 }
    @{ Name = "search_db_mcp";        Port = 9004 }
    @{ Name = "python_chart_mcp";     Port = 9002 }
    @{ Name = "machine_learning_mcp"; Port = 9003 }
    @{ Name = "ywfl_mcp";             Port = 9005 }
    @{ Name = "FastAPI(chat_api)";    Port = 9008 }
)

foreach ($p in $ports) {
    $ok = $false
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $p.Port)
        $ok = $true
        $c.Close()
    } catch { $ok = $false }
    $status = if ($ok) { "OK" } else { "未监听" }
    $color  = if ($ok) { "Green" } else { "Red" }
    Write-Host ("  {0,-22} 端口 {1,-6} [{2}]" -f $p.Name, $p.Port, $status) -ForegroundColor $color
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  测试接口：" -ForegroundColor Cyan
Write-Host "    POST http://localhost:9008/chatbi_service" -ForegroundColor White
Write-Host "    请求体示例：" -ForegroundColor DarkGray
Write-Host '    {"user_id":"u1","message":"查询数据库有哪些表","history":[]}' -ForegroundColor DarkGray
Write-Host ""
Write-Host "  停止所有服务：运行 stop_all.ps1" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
