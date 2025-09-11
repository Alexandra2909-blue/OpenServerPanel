:: --------------------------------------------------------------------------------
:: OPEN SERVER PANEL | DB INIT SCRIPT
:: --------------------------------------------------------------------------------
@echo off
set LC_MESSAGES=English
set "TMP_ROOT=%~dp0.."
for %%I in ("%TMP_ROOT%") do set "TMP_ROOT=%%~fI"
set "OSP_ROOT_DIR=%TMP_ROOT%"
set "OSP_ROOT_DIR_UNIX=%TMP_ROOT:\=/%"
chcp 65001 > nul
TITLE DB Generator
call "%OSP_ROOT_DIR%\generate\genmariadb.bat"
call "%OSP_ROOT_DIR%\generate\genmysql.bat"
call :posgresql PostgreSQL-11
call :posgresql PostgreSQL-12
call :posgresql PostgreSQL-13
call :posgresql PostgreSQL-14
call :posgresql PostgreSQL-15
call :posgresql PostgreSQL-16
call :posgresql PostgreSQL-17
goto end
:: --------------------------------------------------------------------------------
:: INIT PostgreSQL
:: --------------------------------------------------------------------------------
:posgresql
setlocal
powershell -NoLogo -NoProfile -Command ^
  "try { (Get-Content '%OSP_ROOT_DIR%\generate\config\PostgreSQL\postgresql.conf') -replace '{root_dir}', '%OSP_ROOT_DIR%' -replace '{module_name}', '%1' | Set-Content '%OSP_ROOT_DIR%\modules\%1\ospanel_data\default_data\postgresql.conf'; exit 0 } catch { exit 1 }" >nul 2>&1
copy /Y "%OSP_ROOT_DIR%\generate\config\PostgreSQL\pg_hba.conf" "%OSP_ROOT_DIR%\modules\%1\ospanel_data\default_data\pg_hba.conf" >nul 2>&1
set "PGDATA=%OSP_ROOT_DIR%\modules\%1\ospanel_data\default_data"
set "PGCLIENTENCODING=utf-8"
set "PGHOST=127.0.0.1"
set "PGLOCALEDIR=%OSP_ROOT_DIR%\modules\%1\share\locale"
set "PGPORT=5432"
set "PGSSLMODE=disable"
set "PGSYSCONFDIR=%OSP_ROOT_DIR%\modules\%1\ospanel_data\default_data"
set "PGTZ={time_zone}"
set "PGUSER=postgres"
set "TEMP=%OSP_ROOT_DIR%\modules\%1\temp"
set "TMP=%OSP_ROOT_DIR%\modules\%1\temp"
rd "%TMP%" /s /q 2>nul
rd "%PGDATA%" /s /q 2>nul
mkdir "%TMP%" 2>nul
mkdir "%PGDATA%" 2>nul
%OSP_ROOT_DIR%\modules\%1\bin\initdb.exe --data-checksums --no-locale -U postgres --encoding=UTF8 -D "%PGDATA%"
del "%PGDATA%\pg_hba.conf" "%PGDATA%\postgresql.conf"
rd /s /q "%TMP%" 2>nul
endlocal
exit /b 0
:end
echo on
