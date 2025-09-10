:: --------------------------------------------------------------------------------
:: OPEN SERVER PANEL | DB INIT SCRIPT
:: Optimized version with improved error handling and console logging
:: --------------------------------------------------------------------------------
@echo off
setlocal enabledelayedexpansion

:: Initialize variables
set "SCRIPT_START_TIME=%time%"
set "TMP_ROOT=%~dp0.."
for %%I in ("%TMP_ROOT%") do set "TMP_ROOT=%%~fI"
set "OSP_ROOT_DIR=%TMP_ROOT%"
set "OSP_ROOT_DIR_UNIX=%TMP_ROOT:\=/%"

:: Set UTF-8 encoding
chcp 65001 > nul

echo.
echo ================================================================================
echo MARIADB INITIALIZATION SCRIPT
echo ================================================================================
echo [%date% %time%] Starting MariaDB initialization...
echo.

:: Define MariaDB versions array
set "MARIADB_VERSIONS=MariaDB-10.4 MariaDB-10.5 MariaDB-10.6 MariaDB-10.11 MariaDB-11.4 MariaDB-11.8"

:: Process each MariaDB version
for %%V in (%MARIADB_VERSIONS%) do (
    echo [%date% %time%] ^>^>^> Processing %%V...
    call :init_mariadb "%%V"
    if !errorlevel! neq 0 (
        echo [%date% %time%] ❌ ERROR: Failed to initialize %%V
        echo.
        set "HAS_ERRORS=1"
    ) else (
        echo [%date% %time%] ✅ SUCCESS: %%V initialized successfully
        echo.
    )
)

:: Summary
echo ================================================================================
if defined HAS_ERRORS (
    echo [%date% %time%] ❌ Script completed with errors!
    echo Some MariaDB versions failed to initialize. Please check the output above.
    exit /b 1
) else (
    echo [%date% %time%] ✅ All MariaDB versions initialized successfully!
    echo Total execution time: %time% (started at %SCRIPT_START_TIME%)
    exit /b 0
)

:: --------------------------------------------------------------------------------
:: INIT MariaDB with improved error handling and progress indication
:: --------------------------------------------------------------------------------
:init_mariadb
setlocal enabledelayedexpansion
set "VERSION=%~1"
set "mysql_dir=%OSP_ROOT_DIR%\modules\%VERSION%"
set "mysql_dir_unix=%OSP_ROOT_DIR_UNIX%/modules/%VERSION%"

echo     📁 Checking if %VERSION% directory exists...
if not exist "%mysql_dir%" (
    echo     ❌ ERROR: Directory %mysql_dir% does not exist!
    exit /b 1
)

echo     🧹 Cleaning old data directory...
if exist "%mysql_dir%\data" (
    rd /s /q "%mysql_dir%\data" 2>nul
    if exist "%mysql_dir%\data" (
        echo     ⚠️  WARNING: Could not completely remove old data directory
    )
)

:: Set environment variables
call :set_mysql_environment "%mysql_dir%" "%VERSION%"

:: Create necessary directories
echo     📂 Creating directory structure...
call :create_directories "%mysql_dir%"
if !errorlevel! neq 0 exit /b 1

:: Configure my.ini
echo     ⚙️  Configuring my.ini...
call :configure_mysql_ini "%mysql_dir%" "%VERSION%"
if !errorlevel! neq 0 (
    echo     ❌ ERROR: Failed to configure my.ini
    exit /b 1
)

:: Initialize database
echo     💾 Installing database...
cd /d "%mysql_dir%"
copy my.ini my-default.ini >nul 2>&1
copy my.ini my_print_defaults.ini >nul 2>&1

bin\mysql_install_db.exe --datadir="%mysql_dir%\data" --allow-remote-root-access -o
if !errorlevel! neq 0 (
    echo     ❌ ERROR: Database installation failed
    exit /b 1
)

echo     ⏳ Waiting for installation to complete...
timeout /t 3 /nobreak > nul

:: Clean up temporary ini files
del "*.ini" /q >nul 2>&1

:: First startup - timezone configuration
echo     🌍 Configuring timezone settings...
call :configure_mysql_ini "%mysql_dir%" "%VERSION%"
call :start_mysql_and_execute "%mysql_dir%" "%VERSION%" "%OSP_ROOT_DIR%\generate\setup\timezone_posix.sql" "timezone"
if !errorlevel! neq 0 exit /b 1

:: Second startup - main installation
echo     🔧 Running main installation...
copy /Y "%OSP_ROOT_DIR%\generate\config\mariadb\my_configured.ini" "%mysql_dir%\my.ini" >nul
call :replace_placeholders "%mysql_dir%\my.ini" "%OSP_ROOT_DIR_UNIX%" "%VERSION%"
call :start_mysql_and_execute "%mysql_dir%" "%VERSION%" "%OSP_ROOT_DIR%\generate\setup\install.sql" "installation"
if !errorlevel! neq 0 exit /b 1

:: Final cleanup and backup
echo     🧹 Performing final cleanup...
call :final_cleanup "%mysql_dir%"

echo     💾 Creating backup of initialized data...
call :create_data_backup "%mysql_dir%" "%VERSION%"
if !errorlevel! neq 0 (
    echo     ⚠️  WARNING: Data backup failed
)

echo     ✅ %VERSION% initialization completed!

endlocal
exit /b 0

:: --------------------------------------------------------------------------------
:: Helper functions
:: --------------------------------------------------------------------------------

:set_mysql_environment
set "mysql_dir=%~1"
set "version=%~2"
set "DBI_USER="
set "DBI_TRACE="
set "MYSQL_GROUP_SUFFIX="
set "MYSQL_HOME=%mysql_dir%"
set "MYSQL_HOST=127.0.0.1"
set "MYSQL_PS1="
set "MYSQL_PWD="
set "MYSQL_TCP_PORT=3306"
set "MYSQL_UNIX_PORT=%version%"
set "TEMP=%mysql_dir%\temp"
set "TMP=%TEMP%"
set "TMPDIR=%TEMP%"
exit /b 0

:create_directories
set "mysql_dir=%~1"
for %%D in ("%mysql_dir%\temp" "%mysql_dir%\data" "%mysql_dir%\ospanel_data\default_data") do (
    if not exist "%%D" (
        mkdir "%%D" 2>nul
        if not exist "%%D" (
            echo     ❌ ERROR: Failed to create directory %%D
            exit /b 1
        )
    )
)
exit /b 0

:configure_mysql_ini
set "mysql_dir=%~1"
set "version=%~2"
copy /Y "%OSP_ROOT_DIR%\generate\config\mariadb\my.ini" "%mysql_dir%\my.ini" >nul
if !errorlevel! neq 0 (
    echo     ❌ ERROR: Failed to copy my.ini template
    exit /b 1
)
call :replace_placeholders "%mysql_dir%\my.ini" "%OSP_ROOT_DIR_UNIX%" "%version%"
exit /b 0

:replace_placeholders
powershell -NoLogo -NoProfile -Command ^
  "try { (Get-Content '%~1') -replace '{root_dir}', '%~2' -replace '{module_name}', '%~3' | Set-Content '%~1'; exit 0 } catch { exit 1 }" >nul 2>&1
exit /b %errorlevel%

:start_mysql_and_execute
set "mysql_dir=%~1"
set "version=%~2"
set "sql_file=%~3"
set "operation=%~4"

echo       🚀 Starting MySQL server for %operation%...
start "MySQL_%version%_%operation%" bin\mysqld.exe --defaults-file="%mysql_dir%\my.ini" --enable-named-pipe --standalone --console

echo       ⏳ Waiting for server to start...
timeout /t 5 /nobreak > nul

echo       📜 Executing %operation% SQL...
bin\mysql.exe --force --protocol=PIPE --socket=%version% --host="" -u root mysql < "%sql_file%"
set "sql_result=!errorlevel!"

echo       🛑 Shutting down MySQL server...
bin\mysqladmin.exe --protocol=PIPE --socket=%version% --host="" -u root shutdown
timeout /t 5 /nobreak > nul

if !sql_result! neq 0 (
    echo     ❌ ERROR: %operation% SQL execution failed
    exit /b 1
)
exit /b 0

:final_cleanup
set "mysql_dir=%~1"
if exist "%mysql_dir%\temp" rd /s /q "%mysql_dir%\temp" 2>nul
del "%mysql_dir%\data\*.ini" /q >nul 2>&1
del "%mysql_dir%\data\*.err" /q >nul 2>&1
del "%mysql_dir%\*.ini" /q >nul 2>&1
exit /b 0

:create_data_backup
set "mysql_dir=%~1"
set "version=%~2"
robocopy "%mysql_dir%\data" "%OSP_ROOT_DIR%\modules\%version%\ospanel_data\default_data" /UNICODE /DCOPY:DAT /COPY:DAT /TIMFIX /MIR /J /MT:16 /R:2 /W:2 /NFL /NDL >nul 2>&1
if !errorlevel! gtr 7 exit /b 1
rd /s /q "%mysql_dir%\data" 2>nul
exit /b 0