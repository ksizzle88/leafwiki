@echo off
cd /d "%~dp0"
pip install -q -r requirements.txt 2>nul
echo Starting MSSQL Proxy on http://localhost:9999
python server.py
pause
