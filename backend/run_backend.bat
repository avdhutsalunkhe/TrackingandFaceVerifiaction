@echo off
cd /d "%~dp0"
echo Starting FieldStaff AI Attendance Backend Server on port 8084...
if exist venv\Scripts\activate.bat (
    call venv\Scripts\activate.bat
)
set DISABLE_SQLALCHEMY_CEXT=1
python -m uvicorn app.main:app --host 0.0.0.0 --port 8084 --reload
pause
