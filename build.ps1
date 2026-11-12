$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe "/out:$PSScriptRoot\AnnyDesktop.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "$PSScriptRoot\Pet.cs"
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
