# Audit: compare import symbols of a PE (per referenced DLL) against the export tables of those DLLs.
param(
  [string]$DllPath = "D:\Delphi\___Claude Workspace\DDevExtensions\Code\DDevExtensions\D_7\DDevExtensions7.dll",
  [string]$BplDir  = "C:\Delphi\7\Bin"
)

function Read-PE([string]$path) {
  $b = [System.IO.File]::ReadAllBytes($path)
  $peOff = [BitConverter]::ToInt32($b, 0x3C)
  $numSections = [BitConverter]::ToUInt16($b, $peOff + 6)
  $optSize = [BitConverter]::ToUInt16($b, $peOff + 20)
  $optOff = $peOff + 24
  $magic = [BitConverter]::ToUInt16($b, $optOff)
  if ($magic -ne 0x10B) { throw "not PE32: $path" }
  $exportRVA = [BitConverter]::ToUInt32($b, $optOff + 96)
  $exportSize = [BitConverter]::ToUInt32($b, $optOff + 100)
  $importRVA = [BitConverter]::ToUInt32($b, $optOff + 104)
  $secOff = $optOff + $optSize
  $sections = @()
  for ($i = 0; $i -lt $numSections; $i++) {
    $s = $secOff + $i * 40
    $sections += [pscustomobject]@{
      VA   = [BitConverter]::ToUInt32($b, $s + 12)
      VSz  = [BitConverter]::ToUInt32($b, $s + 8)
      Raw  = [BitConverter]::ToUInt32($b, $s + 20)
      RawSz= [BitConverter]::ToUInt32($b, $s + 16)
    }
  }
  [pscustomobject]@{ Bytes = $b; Sections = $sections; ExportRVA = $exportRVA; ExportSize = $exportSize; ImportRVA = $importRVA }
}

function RvaToOff($pe, [uint32]$rva) {
  foreach ($s in $pe.Sections) {
    if (($rva -ge $s.VA) -and ($rva -lt ($s.VA + [Math]::Max($s.VSz, $s.RawSz)))) {
      return $s.Raw + ($rva - $s.VA)
    }
  }
  throw ("bad rva {0:X}" -f $rva)
}

function Read-CStr($pe, [uint32]$rva) {
  $off = RvaToOff $pe $rva
  $end = $off
  while ($pe.Bytes[$end] -ne 0) { $end++ }
  [System.Text.Encoding]::ASCII.GetString($pe.Bytes, $off, $end - $off)
}

function Get-Imports($pe) {
  # returns hashtable dllname(lower) -> [string[]] imported names
  $result = @{}
  if ($pe.ImportRVA -eq 0) { return $result }
  $descOff = RvaToOff $pe $pe.ImportRVA
  while ($true) {
    $oft  = [BitConverter]::ToUInt32($pe.Bytes, $descOff)      # OriginalFirstThunk
    $name = [BitConverter]::ToUInt32($pe.Bytes, $descOff + 12)
    $ft   = [BitConverter]::ToUInt32($pe.Bytes, $descOff + 16) # FirstThunk
    if (($name -eq 0) -and ($ft -eq 0)) { break }
    $dll = (Read-CStr $pe $name).ToLower()
    $thunkRVA = if ($oft -ne 0) { $oft } else { $ft }
    $tOff = RvaToOff $pe $thunkRVA
    $names = New-Object System.Collections.Generic.List[string]
    while ($true) {
      $entry = [BitConverter]::ToUInt32($pe.Bytes, $tOff)
      if ($entry -eq 0) { break }
      if (($entry -band 0x80000000) -ne 0) {
        $names.Add("#ORDINAL:" + ($entry -band 0xFFFF))
      } else {
        $hintNameOff = RvaToOff $pe $entry
        $e = $hintNameOff + 2
        while ($pe.Bytes[$e] -ne 0) { $e++ }
        $names.Add([System.Text.Encoding]::ASCII.GetString($pe.Bytes, $hintNameOff + 2, $e - $hintNameOff - 2))
      }
      $tOff += 4
    }
    if ($result.ContainsKey($dll)) { $result[$dll] += $names.ToArray() } else { $result[$dll] = $names.ToArray() }
    $descOff += 20
  }
  $result
}

function Get-Exports([string]$path) {
  $pe = Read-PE $path
  $set = New-Object 'System.Collections.Generic.HashSet[string]'
  if ($pe.ExportRVA -eq 0) { return $set }
  $eOff = RvaToOff $pe $pe.ExportRVA
  $numNames = [BitConverter]::ToUInt32($pe.Bytes, $eOff + 24)
  $namesRVA = [BitConverter]::ToUInt32($pe.Bytes, $eOff + 32)
  $nOff = RvaToOff $pe $namesRVA
  for ($i = 0; $i -lt $numNames; $i++) {
    $rva = [BitConverter]::ToUInt32($pe.Bytes, $nOff + $i * 4)
    [void]$set.Add((Read-CStr $pe $rva))
  }
  , $set
}

$pe = Read-PE $DllPath
$imports = Get-Imports $pe
"Referenced DLLs:"
$imports.Keys | Sort-Object | ForEach-Object { "  $_  ($($imports[$_].Count) symbols)" }
""
foreach ($dll in ($imports.Keys | Sort-Object)) {
  if ($dll -match '^(kernel32|user32|gdi32|advapi32|ole32|oleaut32|comctl32|comdlg32|shell32|version|winspool|wininet|winmm|imm32|shlwapi|oleacc|msvcrt|netapi32|mpr|psapi|wsock32|ws2_32)\.dll$') { continue }
  $target = Join-Path $BplDir $dll
  if (-not (Test-Path $target)) { "!! $dll NOT FOUND in $BplDir"; continue }
  $exports = Get-Exports $target
  $missing = @($imports[$dll] | Where-Object { -not $exports.Contains($_) })
  if ($missing.Count -gt 0) {
    "== $dll : $($missing.Count) MISSING of $($imports[$dll].Count) =="
    $missing | ForEach-Object { "   $_" }
  } else {
    "OK $dll ($($imports[$dll].Count) symbols)"
  }
}
