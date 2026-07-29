@echo off
setlocal

:: Access the full path using ZED_FILE
set "full_path=%ZED_FILE%"

:: Extract filename with extension
for %%f in ("%full_path%") do set "filename_ext=%%~nxf"

:: Extract filename without extension and extension separately
for %%f in ("%filename_ext%") do (
    set "filename=%%~nf.exe"
    set "extension=%%~xf"
)

:: Remove the leading dot from extension
set "extension=%extension:~1%"

echo [running %filename_ext%]

if /I "%extension%" == "cpp" (
    g++ -std=c++26 -o "%filename%" "%full_path%" && "%filename%"
    del "%filename%"
) else if /I "%extension%" == "py" (
    python "%full_path%"
) else if /I "%extension%" == "c" (
    gcc -o "%filename%" "%full_path%" && "%filename%"
    del "%filename%"
) else if /I "%extension%" == "lua" (
    lua "%full_path%"
) else if /I "%extension%" == "rs" (
    rustc "%full_path%" -o "%filename%" && "%filename%"
    del "%filename%"
) else if /I "%extension%" == "go" (
    go run "%full_path%"
) else if /I "%extension%" == "js" (
    bun run "%full_path%"
) else if /I "%extension%" == "ts" (
    bun run "%full_path%"
) else (
    echo no
)

endlocal