@echo off
chcp 65001 >nul
echo ╔══════════════════════════════════════════════╗
echo ║   ClearCall 信令中继 — 本地开发服务器         ║
echo ╚══════════════════════════════════════════════╝
echo.

cd /d "%~dp0"

echo [1/3] 检查 Dart 环境...
where dart >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERROR] 未找到 Dart SDK，请先安装: https://dart.dev/get-dart
    pause
    exit /b 1
)
echo   Dart 环境就绪

echo [2/3] 安装依赖...
call dart pub get
if %errorlevel% neq 0 (
    echo  [ERROR] 依赖安装失败
    pause
    exit /b 1
)
echo   依赖就绪

echo [3/3] 启动服务器...
echo.
echo   服务器地址: http://localhost:8080
echo   WebSocket:   ws://localhost:8080/ws
echo   按 Ctrl+C 停止
echo.

dart run server.dart --port=8080
