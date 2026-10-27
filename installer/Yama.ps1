param([ValidateSet('Kur','GeriAl')][string]$Islem = 'Kur', [string]$Klasor)
$ErrorActionPreference = 'Stop'
function Hash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Regular([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Normal dosya degil: $Path" }
}
function RealDirectory([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { throw 'Klasor bulunamadi.' }
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Baglanti klasoru desteklenmiyor. Gercek klasoru secin.' }
        $item = $item.Parent
    }
}
$interactive = -not $Klasor
try {
    if ($interactive) {
        Add-Type -AssemblyName System.Windows.Forms
        $picker = New-Object Windows.Forms.FolderBrowserDialog
        $picker.Description = if ($Islem -eq 'Kur') { 'Death Stranding 2 ana oyun klasorunu secin' } else { 'Oyun icindeki DS2-Yama-Yedek-* klasorunu secin' }
        if ($picker.ShowDialog() -ne 'OK') { exit 0 }
        $Klasor = $picker.SelectedPath
        $picker.Dispose()
    }
    RealDirectory $Klasor
    $selected = (Get-Item -LiteralPath $Klasor).FullName
    $legacyName = 'DS2_' + 'Play' + 'Ceviri_TR.dat'
    $names = @('winhttp.dll','DS2_Turkce.dat','DS2_Intro.dll')
    if ($Islem -eq 'Kur') {
        $target = $selected
        $marker = Join-Path $target 'LocalCacheWinGame\package\package.40.11.core.stream'
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { throw 'Bu klasorde DS2 oyun verisi bulunamadi. LocalCacheWinGame klasorunun bulundugu ana oyun klasorunu secin.' }
        Regular $marker
        $rows = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'dosyalar.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($rows.Count -ne 3 -or @($rows.path | Select-Object -Unique).Count -ne 3) { throw 'Paket dosya listesi gecersiz.' }
        foreach ($row in $rows) {
            if ($row.path -notin $names) { throw 'Paket dosya adi gecersiz.' }
            $source = Join-Path (Join-Path $PSScriptRoot 'Dosyalar') $row.path
            Regular $source
            if ((Hash $source) -ne $row.sha256) { throw "Paket butunluk kontrolu basarisiz: $($row.path)" }
            $dest = Join-Path $target $row.path
            if (Test-Path -LiteralPath $dest) {
                Regular $dest
                if ($row.path -eq 'DS2_Intro.dll' -and (Hash $dest) -ne $row.sha256) { throw 'Kaynak disi DS2_Intro.dll var; kurulum durduruldu.' }
                if ($row.path -eq 'winhttp.dll' -and (Hash $dest) -notin @($row.sha256, 'caf6367826663d01d37d01f795756297fdc7ffce02be406dd45536b2ff16c8eb', '18990667c58d098aaf1ef94d838f11498b25561a1997f3faeec297f657198842', 'c8442169f53095a18a4afab57194d03de5d7504ea0ea89f31b50122f7df3c935', '1898cacb9895dff613009ad3f0db41f6bc6af49ee08901c5faec953aa3f9c68e')) {
                    throw 'Baska bir moda ait olabilecek winhttp.dll var. Cakismayi onlemek icin kurulum durduruldu.'
                }
            }
        }
        $legacyPath = Join-Path $target $legacyName
        $legacyExists = Test-Path -LiteralPath $legacyPath
        if ($legacyExists) {
            Regular $legacyPath
            if ((Hash $legacyPath) -ne 'd2a84b22dde7e456da5bc089183fb595393398bfcb507b616e4edab97be82c39') { throw 'Eski yama veri dosyasi degismis; kurulum durduruldu.' }
        }
        $backup = Join-Path $target ('DS2-Yama-Yedek-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $backup | Out-Null
        $state = @()
        foreach ($row in $rows) {
            $dest = Join-Path $target $row.path
            $exists = Test-Path -LiteralPath $dest
            $original = $null
            if ($exists) {
                $original = Hash $dest
                $saved = Join-Path $backup $row.path
                Copy-Item -LiteralPath $dest -Destination $saved
                if ((Hash $saved) -ne $original) { throw 'Yedek dogrulanamadi; oyun dosyalari degistirilmedi.' }
            }
            $state += [pscustomobject]@{path=$row.path; existed=$exists; original_sha256=$original; sha256=$row.sha256}
        }
        if ($legacyExists) {
            $saved = Join-Path $backup $legacyName
            Copy-Item -LiteralPath $legacyPath -Destination $saved
            if ((Hash $saved) -ne (Hash $legacyPath)) { throw 'Eski veri yedegi dogrulanamadi.' }
            $state += [pscustomobject]@{path=$legacyName; existed=$true; original_sha256=(Hash $saved); sha256=$null; removed=$true}
        }
        [pscustomobject]@{gameDirectory=$target; files=$state} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'kurulum-kaydi.json') -Encoding UTF8
        $changed = @()
        try {
            foreach ($row in $rows) {
                $changed += $row.path
                $dest = Join-Path $target $row.path
                if (Test-Path -LiteralPath $dest) { [IO.File]::SetAttributes($dest, [IO.FileAttributes]::Normal) }
                Copy-Item -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'Dosyalar') $row.path) -Destination $dest -Force
                if ((Hash $dest) -ne $row.sha256) { throw 'Kopyalanan dosya dogrulanamadi.' }
            }
            if ($legacyExists) {
                $changed += $legacyName
                Remove-Item -LiteralPath $legacyPath -Force
            }
        } catch {
            $reason = $_.Exception.Message
            $rollbackErrors = @()
            foreach ($entry in $state) {
                if ($entry.path -notin $changed) { continue }
                try {
                    $dest = Join-Path $target $entry.path
                    if ($entry.existed) {
                        Copy-Item -LiteralPath (Join-Path $backup $entry.path) -Destination $dest -Force
                        if ((Hash $dest) -ne $entry.original_sha256) { throw 'Geri kopya dogrulanamadi.' }
                    } elseif (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
                } catch { $rollbackErrors += $_.Exception.Message }
            }
            if ($rollbackErrors.Count) { throw "$reason Geri alma tamamlanamadi: $($rollbackErrors -join '; '). Yedek: $backup" }
            throw "$reason Degisiklikler geri alindi."
        }
        $message = "Yama dosyalari kuruldu. Yedek: $backup"
    } else {
        $backup = $selected
        $directory = Get-Item -LiteralPath $backup
        if ($directory.Name -notlike 'DS2-Yama-Yedek-*') { throw 'DS2-Yama-Yedek-* klasorunu secin.' }
        $target = $directory.Parent.FullName
        $recordPath = Join-Path $backup 'kurulum-kaydi.json'
        Regular $recordPath
        $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($record.gameDirectory -ne $target) { throw 'Yedek kayitli oyun klasorunde degil.' }
        $rows = @($record.files)
        if ($rows.Count -lt 2 -or $rows.Count -gt 4 -or @($rows.path | Select-Object -Unique).Count -ne $rows.Count) { throw 'Gecersiz kurulum kaydi.' }
        $names += $legacyName
        foreach ($row in $rows) {
            if ($row.path -notin $names) { throw 'Gecersiz dosya adi.' }
            if ($row.existed) {
                $saved = Join-Path $backup $row.path
                Regular $saved
                if ((Hash $saved) -ne $row.original_sha256) { throw 'Yedek dosya degismis; geri alma durduruldu.' }
            }
            $dest = Join-Path $target $row.path
            if (Test-Path -LiteralPath $dest) {
                Regular $dest
                if ((Hash $dest) -notin @($row.sha256, $row.original_sha256)) { throw 'Kurulumdan sonra degisen dosya var; geri alma durduruldu.' }
            }
        }
        foreach ($row in $rows) {
            $dest = Join-Path $target $row.path
            if ($row.existed) {
                Copy-Item -LiteralPath (Join-Path $backup $row.path) -Destination $dest -Force
                if ((Hash $dest) -ne $row.original_sha256) { throw 'Geri alinan dosya dogrulanamadi.' }
            } elseif (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
        }
        $message = 'Yama geri alindi. Yedek klasoru saklandi.'
    }
    Write-Output $message
    if ($interactive) { [Windows.Forms.MessageBox]::Show($message, 'DS2 Turkce Yama') | Out-Null }
} catch {
    if ($interactive) { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Islem tamamlanamadi') | Out-Null }
    Write-Error $_
    exit 1
}


