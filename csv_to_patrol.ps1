# jonghap_new.csv → patrol_data.js 변환 (파이썬 불필요, 윈도우 기본 PowerShell)
# 대시보드는 patrol_data.js를 열 때 자동으로 읽습니다. 이 스크립트는 CSV가 바뀌면 그 파일을 갱신합니다.
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$csv = Join-Path $dir 'jonghap_new.csv'
$out = Join-Path $dir 'patrol_data.js'

$lines = Get-Content -LiteralPath $csv -Encoding UTF8
$rows = @()
foreach ($l in $lines) { $rows += ,($l -split ',') }

# 헤더행(구분 / 점검구분) 찾기
$hr = -1
for ($i = 0; $i -lt $rows.Count; $i++) {
    $r = $rows[$i]
    if ($r.Count -gt 2 -and $r[0].Trim() -eq '구분' -and $r[2].Trim() -eq '점검구분') { $hr = $i; break }
}
if ($hr -lt 1) { Write-Error 'CSV 헤더(구분/점검구분)를 찾지 못했습니다.'; exit 1 }

$per = $rows[$hr - 1]
$sub = $rows[$hr]
$want = @('2026년 누적','5월 누적','1분기','2분기','3분기','4분기')
$pcol = @{}
for ($c = 0; $c -lt $sub.Count; $c++) {
    if ($sub[$c].Trim() -eq '발굴') {
        $lab = if ($c -lt $per.Count) { $per[$c].Trim() } else { '' }
        if (($want -contains $lab) -and (-not $pcol.ContainsKey($lab))) { $pcol[$lab] = @($c, ($c + 1)) }
    }
}

function CatOf($s) {
    $s = $s.Trim()
    if ($s -eq '총계' -or $s -eq '소계') { return '계' }
    if ($s.StartsWith('01')) { return '일반' }
    if ($s.StartsWith('02')) { return '위험성평가' }
    if ($s.StartsWith('03')) { return '테마별순회점검' }
    if ($s.StartsWith('04')) { return '정기순회점검' }
    return $null
}
function ToNum($v) {
    $v = ($v -replace '[^0-9-]', '')
    if ($v -eq '' -or $v -eq '-') { return $null }
    return [int]$v
}

$facs = @('CTR Mobility','10-울산','30-서산','40-대구')
$d = [ordered]@{}
$cur = $null
for ($i = $hr + 1; $i -lt $rows.Count; $i++) {
    $r = $rows[$i]
    if ($r.Count -gt 0 -and $r[0].Trim() -eq 'END') { break }
    $f0 = if ($r.Count -gt 0) { $r[0].Trim() } else { '' }
    $f1 = if ($r.Count -gt 1) { $r[1].Trim() } else { '' }
    if ($facs -contains $f0) { $cur = $f0 } elseif ($facs -contains $f1) { $cur = $f1 }
    if (-not $cur) { continue }
    $cat = if ($r.Count -gt 2) { CatOf $r[2] } else { $null }
    if (-not $cat) { continue }
    if (-not $d.Contains($cur)) { $d[$cur] = [ordered]@{} }
    foreach ($p in $pcol.Keys) {
        $fc = $pcol[$p][0]; $dc = $pcol[$p][1]
        $f  = if ($fc -lt $r.Count) { ToNum $r[$fc] } else { $null }
        $dn = if ($dc -lt $r.Count) { ToNum $r[$dc] } else { $null }
        if ($null -eq $f -and $null -eq $dn) { continue }
        if (-not $d[$cur].Contains($p)) { $d[$cur][$p] = [ordered]@{} }
        $fv = if ($null -eq $f) { 0 } else { $f }
        $dv = if ($null -eq $dn) { 0 } else { $dn }
        $d[$cur][$p][$cat] = @($fv, $dv)
    }
}

# 빈 기간(계 없음/0) 제거
foreach ($fac in @($d.Keys)) {
    foreach ($p in @($d[$fac].Keys)) {
        $t = $d[$fac][$p]['계']
        if ($null -eq $t -or ($t[0] -eq 0 -and $t[1] -eq 0)) { $d[$fac].Remove($p) }
    }
}

$obj = [ordered]@{ stamp = ((Get-Date -Format 'yyyy-MM-dd') + ' 기준'); d = $d }
$json = $obj | ConvertTo-Json -Depth 10 -Compress
$js = 'window.PATROL_DATA = ' + $json + ';'
[System.IO.File]::WriteAllText($out, $js, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('patrol_data.js 갱신 완료 -> ' + $out)
