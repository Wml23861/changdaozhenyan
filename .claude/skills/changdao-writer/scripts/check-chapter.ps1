# check-chapter.ps1
# 《唱道真言》爽文版章节机器校验脚本
# 依据《资料/00_作品说明与连载大纲.md》第五节"写作排版规范"及人工特性指标实现。
# 用法: powershell -File check-chapter.ps1 -Path <章节md路径>
# 退出码: 0 = 通过(可有警告); 1 = 存在错误; 2 = 参数/文件问题

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorCount = 0
$WarnCount  = 0

function Fail($msg) { $script:ErrorCount++; Write-Host "[错误] $msg" }
function Warn($msg) { $script:WarnCount++;  Write-Host "[警告] $msg" }
function Ok($msg)   { Write-Host "[通过] $msg" }

if (-not (Test-Path $Path)) {
    Write-Host "[错误] 文件不存在: $Path"
    exit 2
}

$fileName = [System.IO.Path]::GetFileName($Path)
$raw  = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
$text = $raw -replace "`r`n", "`n" -replace "`r", "`n"
$lines = $text -split "`n"

Write-Host "===== 章节机器校验: $fileName ====="

# ---------- 1. 文件名规范: 第NNN章_标题.md ----------
$numFromFile = -1
if ($fileName -match '^第(\d{3})章_(.+)\.md$') {
    $numFromFile = [int]$Matches[1]
    Ok "文件名规范(第${numFromFile}章)"
} else {
    Fail "文件名不符合 '第NNN章_标题.md' 规范: $fileName"
}

# ---------- 2. 首行标题: # 第N章 标题 ----------
$numFromTitle = -1
if ($lines.Count -gt 0 -and $lines[0] -match '^# 第(\d+)章[ 　]+(\S.*)$') {
    $numFromTitle = [int]$Matches[1]
    Ok "首行标题格式"
} else {
    Fail "首行必须是 '# 第N章 标题' 格式的一级标题, 实际: $($lines[0])"
}

# ---------- 3. 文件名与标题章号一致 ----------
if ($numFromFile -ge 0 -and $numFromTitle -ge 0) {
    if ($numFromFile -eq $numFromTitle) {
        Ok "章号一致($numFromFile)"
    } else {
        Fail "文件名章号($numFromFile) 与标题章号($numFromTitle) 不一致"
    }
}

# ---------- 4. 正文与收尾 ----------
$bodyLines = @()
if ($lines.Count -gt 1) { $bodyLines = $lines[1..($lines.Count - 1)] }
$body = ($bodyLines -join "`n").Trim()

$nonEmpty = @($bodyLines | Where-Object { $_.Trim() -ne "" })
if ($nonEmpty.Count -eq 0) {
    Fail "正文为空"
    Write-Host "===== 结果: 错误 $ErrorCount, 警告 $WarnCount ====="
    exit 1
}

# 注: 自 9f7e981 起全书不再使用"（本章完）"章尾标记, 不再强制检查

# 内容正文(去掉章尾标记)
$contentParas = @($nonEmpty | Where-Object { $_.Trim() -ne '（本章完）' } | ForEach-Object { $_.Trim() })
$content = $contentParas -join "`n"

# ---------- 5. 字数: 正文2500字以上 ----------
$charCount = ($content -replace '\s', '').Length
if ($charCount -ge 2500) {
    Ok "字数达标($charCount 字 >= 2500)"
} else {
    Fail "字数不足: $charCount 字 < 2500 字"
}

# ---------- 6. 禁用标点: 破折号、省略号及各类特殊符号 ----------
$forbiddenMap = [ordered]@{
    '——' = '破折号(双)'; '—' = '破折号'; '–' = '连接号'; '―' = '横线号';
    '……' = '省略号(双)'; '…' = '省略号'; '···' = '省略号(点式)';
    '「' = '直角引号'; '」' = '直角引号'; '『' = '直角双引号'; '』' = '直角双引号';
    '*' = '星号(Markdown)'; '`' = '反引号(Markdown)'
}
foreach ($key in $forbiddenMap.Keys) {
    $cnt = [regex]::Matches($content, [regex]::Escape($key)).Count
    if ($cnt -gt 0) { Fail "出现禁用符号 $($forbiddenMap[$key]) '$key' 共 $cnt 处" }
}
# Markdown 格式行
foreach ($p in $contentParas) {
    if ($p -match '^[#>\-\d+\.]') { Warn "疑似 Markdown 格式行: $($p.Substring(0, [Math]::Min(20, $p.Length)))..." }
}
if ($ErrorCount -eq 0) { Ok "无禁用标点与 Markdown 符号" }

# ---------- 7. 规范2: 单句短段只作节奏顿点单发, 不得连续两段连用 ----------
$soloRun = 0
$paraIssue = 0
foreach ($p in $contentParas) {
    $m = [regex]::Match($p, '[，。？！：；、""''《》（）]')
    if ($m.Success -and $m.Value -eq '。') {
        $soloRun++
        if ($soloRun -ge 2) {
            Fail "单句短段连续连用(开头句必须有逗号, 短段不得连用): $($p.Substring(0, [Math]::Min(25, $p.Length)))..."
            $paraIssue++
        }
    } else {
        $soloRun = 0
    }
}
if ($paraIssue -eq 0) { Ok "单句短段无连续连用, 节奏顿点合规" }

# ---------- 7.5 规范7: 段落长度适配手机阅读 ----------
# 叙事段目标<=80字, 对话/讲经/经文段目标<=100字, 任何段落不得>150字
$longParaWarn = 0
$longParaFail = 0
foreach ($p in $contentParas) {
    $plen = ($p -replace '\s', '').Length
    if ($plen -gt 150) {
        Fail "段落超长($plen 字 > 150), 手机端整屏文字墙, 必须拆段: $($p.Substring(0, [Math]::Min(20, $p.Length)))..."
        $longParaFail++
    } elseif ($plen -gt 100) {
        Warn "段落偏长($plen 字 > 100), 建议拆段: $($p.Substring(0, [Math]::Min(20, $p.Length)))..."
        $longParaWarn++
    }
}
if ($longParaWarn -eq 0 -and $longParaFail -eq 0) { Ok "段落长度适配手机阅读(全部 <= 100 字)" }

# ---------- 7.6 规范8: 段尾必须以句号/问号收束, 禁止逗号悬空 ----------
$paraEndFail = 0
foreach ($p in $contentParas) {
    $pt = $p.TrimEnd()
    # 去掉段尾闭口引号后, 看最后一个字符是否为非句末标点
    $core = $pt -replace '[”"]+$', ''
    if ($core -match '[，、；,;]$') {
        $tail = $core.Substring([Math]::Max(0, $core.Length - 20))
        Fail "段尾以逗号/顿号悬空收尾(必须以句号或问号收束): ...$tail"
        $paraEndFail++
    }
}
if ($paraEndFail -eq 0) { Ok "所有段落均以句号/问号/冒号收束, 无逗号悬空" }

# ---------- 7.7 规范8: 句末标点密度(防一逗到底) ----------
$endMarkCnt = [regex]::Matches($content, '[。？！]').Count
$commaTotal = [regex]::Matches($content, '，').Count
if ($commaTotal -gt 0) {
    if ($endMarkCnt * 12 -ge $commaTotal) {
        Ok "句末标点密度达标(句末 $endMarkCnt : 逗号 $commaTotal, 不低于 1:12)"
    } else {
        Warn "句末标点密度过低(句末 $endMarkCnt : 逗号 $commaTotal, 低于 1:12), 疑似一逗到底, 需人工评估"
    }
}

# ---------- 8. 规范1/3: 句号收尾的句子成分检查 ----------
# 按句号/问号/叹号切句
$sentences = @()
foreach ($seg in [regex]::Split($content, '[。？！]')) {
    $s = ($seg -replace '\s', '' -replace '[""''《》（）]', '')
    if ($s.Length -gt 0) { $sentences += $s }
}

$shortNoComma = 0
$oneCommaShort = 0
$consecShort   = 0
$prevLen = 999
$lengths = @()
foreach ($s in $sentences) {
    $len = $s.Length
    $lengths += $len
    $commaCnt = [regex]::Matches($s, '，').Count
    if ($len -le 6 -and $commaCnt -eq 0) {
        $shortNoComma++
        if ($shortNoComma -le 5) { Warn "超短句独立收尾(建议并入长句): '$s'" }
    }
    if ($len -le 12 -and $len -gt 6 -and $commaCnt -le 1) {
        $oneCommaShort++
        if ($oneCommaShort -le 5) { Warn "句子成分单薄(一逗一句): '$s'" }
    }
    if ($len -le 8 -and $prevLen -le 8) {
        $consecShort++
        Warn "连续短句连用: '$s'"
    }
    $prevLen = $len
}
if ($shortNoComma -eq 0 -and $consecShort -eq 0) { Ok "无连续短句/超短句收尾" }
if ($oneCommaShort -eq 0) { Ok "句子成分完整度达标" }

# ---------- 9. 人工特性: 句长节奏(长句为主, 长短交错) ----------
$total = 0; foreach ($l in $lengths) { $total += $l }
$avg = [Math]::Round($total / [Math]::Max(1, $lengths.Count), 1)
$maxLen = ($lengths | Measure-Object -Maximum).Maximum
$minLen = ($lengths | Measure-Object -Minimum).Minimum
if ($avg -ge 18) { Ok "平均句长 $avg 字(>=18, 符合长句风格)" } else { Warn "平均句长 $avg 字偏短(<18), 与全书长句风格不符" }
if ($maxLen -ge 40) { Ok "最长句 $maxLen 字(>=40, 节奏有起伏)" } else { Warn "最长句 $maxLen 字偏短(<40), 缺少长句铺陈" }

# ---------- 10. 人工特性: AI腔词汇扫描 ----------
$aiCliches = @(
    '不禁', '不由得', '情不自禁', '宛如', '犹如', '霎时间', '刹那间', '顷刻间',
    '这一刻', '下一秒', '值得一提', '众所周知', '总而言之', '综上所述',
    '毋庸置疑', '毫无疑问', '嘴角勾起', '勾起一抹', '闪过一丝', '眼中闪过',
    '眸光', '深邃', '内心涌起', '一股暖流', '震撼不已', '心潮澎湃',
    '感慨万千', '思绪万千', '陷入沉思', '意味深长', '若有所思', '露出笑容'
)
$clicheHits = 0

# 经文引文豁免: 引号内照录《资料/原文对照.md》原文的词不计入(经文须逐字照引, 不可改写)
# 注意: 本段全部用字符编码构造, 不写中文引号/标点字面量, 避免脚本编码差异导致正则失配
function ConvertTo-FlatText($s) { return ($s -replace '[^0-9A-Za-z一-鿿]', '') }

$canonFlat = ''
$bookDir  = Split-Path (Split-Path (Split-Path $Path -Parent) -Parent) -Parent
$canonPath = Join-Path $bookDir '资料\原文对照.md'
if (Test-Path $canonPath) {
    $canonRaw  = [System.IO.File]::ReadAllText($canonPath, [System.Text.Encoding]::UTF8)
    $canonFlat = ConvertTo-FlatText $canonRaw
}
$script:canonFlatRef = $canonFlat

$lq = [char]0x201C; $rq = [char]0x201D
$spanPattern = "$lq[^$rq]*$rq"
$quoteSpans = New-Object System.Collections.ArrayList
foreach ($m in [regex]::Matches($content, $spanPattern)) {
    # 注意: PowerShell 逗号优先级高于加法, 求和必须加括号
    [void]$quoteSpans.Add(@($m.Index, ($m.Index + $m.Length)))
}
$script:quoteSpansRef = $quoteSpans

function Test-ScriptureQuote($idx, $len) {
    if ($script:canonFlatRef -eq '') { return $false }
    foreach ($sp in $script:quoteSpansRef) {
        if ($idx -ge $sp[0] -and ($idx + $len) -le $sp[1]) {
            $quoteText = $content.Substring($sp[0], $sp[1] - $sp[0])
            $qFlat = ConvertTo-FlatText $quoteText
            if ($qFlat.Length -ge 6 -and $script:canonFlatRef.Contains($qFlat)) { return $true }
            $pos    = $idx - $sp[0]
            $wStart = [Math]::Max(0, $pos - 12)
            $wLen   = [Math]::Min($quoteText.Length - $wStart, $len + 24)
            $winFlat = ConvertTo-FlatText ($quoteText.Substring($wStart, $wLen))
            if ($winFlat.Length -ge 8 -and $script:canonFlatRef.Contains($winFlat)) { return $true }
            return $false
        }
    }
    return $false
}

foreach ($w in $aiCliches) {
    $cnt = 0
    foreach ($m in [regex]::Matches($content, [regex]::Escape($w))) {
        if (-not (Test-ScriptureQuote $m.Index $m.Length)) { $cnt++ }
    }
    if ($cnt -gt 0) {
        $clicheHits += $cnt
        Warn "AI腔/套路词汇 '$w' 出现 $cnt 次"
    }
}
if ($clicheHits -eq 0) { Ok "未检出AI腔套路词汇(经文引文已豁免)" }

# ---------- 11. 人工特性: 段落开头重复率 ----------
$starters = @{}
foreach ($p in $contentParas) {
    if ($p.Length -ge 3) {
        $head = $p.Substring(0, 3)
        if ($starters.ContainsKey($head)) { $starters[$head]++ } else { $starters[$head] = 1 }
    }
}
$dupStarters = 0
foreach ($k in $starters.Keys) {
    if ($starters[$k] -ge 3) {
        $dupStarters++
        Warn "段落开头 '$k...' 重复 $($starters[$k]) 次"
    }
}
if ($dupStarters -eq 0) { Ok "段落开头无明显重复" }

# ---------- 结果汇总 ----------
Write-Host "===== 结果: 错误 $ErrorCount, 警告 $WarnCount ====="
if ($ErrorCount -gt 0) { exit 1 } else { exit 0 }
