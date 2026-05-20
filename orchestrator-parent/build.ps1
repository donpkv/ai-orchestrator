#Requires -Version 5.1
<#
.SYNOPSIS
    Build all modules using project-local Maven settings (bypasses corporate Nexus).

.DESCRIPTION
    Sets JAVA_HOME to Java 21, then runs mvn with the project-local settings.xml
    that points directly to Maven Central.

    Usage:
        .\build.ps1              -- compile + package, skip tests
        .\build.ps1 -RunTests    -- compile + package + run tests
        .\build.ps1 -Module workflow-controller  -- build single module only
#>

param(
    [switch]$RunTests,
    [string]$Module = ""
)

# Set Java 21 for this session
$jdk21 = Get-ChildItem "C:\Program Files\Eclipse Adoptium\" -Directory `
    | Where-Object { $_.Name -like "jdk-21*" } `
    | Select-Object -First 1 -ExpandProperty FullName

if (-not $jdk21) {
    Write-Host "Java 21 not found in C:\Program Files\Eclipse Adoptium\" -ForegroundColor Red
    Write-Host "Install with: winget install EclipseAdoptium.Temurin.21.JDK" -ForegroundColor Yellow
    exit 1
}

$env:JAVA_HOME = $jdk21
$env:PATH = "$env:JAVA_HOME\bin;" + $env:PATH
Write-Host "Using Java: $(java -version 2>&1 | Select-Object -First 1)" -ForegroundColor Gray

$skipTests = if ($RunTests) { "" } else { "-DskipTests" }
$moduleFlag = if ($Module) { "-pl $Module -am" } else { "" }

$cmd = "mvn -s .mvn/settings.xml clean install $skipTests $moduleFlag"
Write-Host "Running: $cmd" -ForegroundColor Cyan
Invoke-Expression $cmd
