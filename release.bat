@echo off
if "%~1"=="" (
  echo Usage: release 1.2.0
  exit /b 1
)
git push && git tag v%~1 && git push origin v%~1
echo.
echo Tag v%~1 pushed. GitHub is building the release now - see the Actions tab.
