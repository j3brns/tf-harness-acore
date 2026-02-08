@echo off
setlocal enabledelayedexpansion

rem Run from repo root regardless of invocation directory
pushd "%~dp0"

rem Resolve Terraform binary
set "TERRAFORM=terraform"
where terraform >nul 2>&1
if errorlevel 1 (
  if exist "C:\tools\terraform\terraform.exe" (
    set "TERRAFORM=C:\tools\terraform\terraform.exe"
  ) else (
    echo ERROR: terraform not found in PATH and C:\tools\terraform\terraform.exe not found.
    popd
    exit /b 1
  )
)

if /I "%~1"=="--fix" (
  echo === Minimal validation (with auto-fix^) ===
  echo Running: terraform fmt -recursive
  "%TERRAFORM%" fmt -recursive
  if errorlevel 1 goto :fail
)

echo === Minimal validation ===
echo Running: terraform fmt -check -recursive
"%TERRAFORM%" fmt -check -recursive
if errorlevel 1 goto :fail

set "PRECOMMIT_CMD="
where uv >nul 2>&1
if errorlevel 0 (
  uv tool run pre-commit --version >nul 2>&1
  if errorlevel 0 set "PRECOMMIT_CMD=uv tool run pre-commit"
)

if "%PRECOMMIT_CMD%"=="" (
  where pre-commit >nul 2>&1
  if errorlevel 0 (
    pre-commit --version >nul 2>&1
    if errorlevel 0 set "PRECOMMIT_CMD=pre-commit"
  )
)

if "%PRECOMMIT_CMD%"=="" (
  where py >nul 2>&1
  if errorlevel 0 (
    py -3.12 -m pre_commit --version >nul 2>&1
    if errorlevel 0 set "PRECOMMIT_CMD=py -3.12 -m pre_commit"
  )
)

if "%PRECOMMIT_CMD%"=="" (
  where python >nul 2>&1
  if errorlevel 0 (
    python -m pre_commit --version >nul 2>&1
    if errorlevel 0 set "PRECOMMIT_CMD=python -m pre_commit"
  )
)

if "%PRECOMMIT_CMD%"=="" (
  echo ERROR: pre-commit not found. Install with:
  echo   uv tool install pre-commit
  echo Or:
  echo   py -3.12 -m pip install pre-commit
  echo Or:
  echo   pipx install pre-commit
  goto :fail
)

set "SKIP=terraform_fmt,terraform_validate,terraform_docs,terraform_tflint,terraform_checkov"
echo Running: %PRECOMMIT_CMD% run --all-files (SKIP=%SKIP%)
call %PRECOMMIT_CMD% run --all-files
if errorlevel 1 goto :fail

echo.
echo SUCCESS: Minimal validation completed.
popd
exit /b 0

:fail
echo.
echo FAILED: Validation did not complete successfully.
popd
exit /b 1
