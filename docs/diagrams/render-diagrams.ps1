$diagDir = "$PSScriptRoot"
$outDir  = "$diagDir\images"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$files = Get-ChildItem "$diagDir\diagram-*.md" | Sort-Object Name

foreach ($f in $files) {
    $name   = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $outPng   = "$outDir\$name.png"
    $outPng1  = "$outDir\$name-1.png"  # mmdc appends -1 when input is a .md file
    Write-Host "Rendering $($f.Name) ..." -ForegroundColor Cyan
    mmdc -i "$($f.FullName)" -o "$outPng" -b white -w 1600 --quiet
    # mmdc names the output file "<name>-1.png" when the source is Markdown
    if ((Test-Path $outPng) -or (Test-Path $outPng1)) {
        Write-Host "  OK  -> images\$name-1.png" -ForegroundColor Green
    } else {
        Write-Host "  FAILED for $($f.Name)" -ForegroundColor Red
    }
}

Write-Host "`nAll done. Images saved to: $outDir" -ForegroundColor Yellow
