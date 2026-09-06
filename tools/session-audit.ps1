<#
session-audit.ps1 —— 会话导出 JSON 降维审计器（本机：Windows + PowerShell 5.1）

用途：把几 MB 的 CodeBuddy 会话导出（schema `codebuddy.conversation`）压成一份
      可直读的 digest，供 `docs/agents/audit-runbooks.md` Runbook B（会话导出审计）
      逐条填档。导出件通常 1MB 以上，直接读会爆上下文，必须先降维。

用法：
  powershell -File tools/session-audit.ps1 -InputFile <导出.json>
  powershell -File tools/session-audit.ps1 -InputFile <导出.json> -TimelineOnly
  powershell -File tools/session-audit.ps1 -InputFile <导出.json> -IncludeReasoning

输出：默认 <输入文件名>.digest.txt（同目录）。建议把导出件放 `.codebuddy/audit/`
      （被 gitignore，不入仓库，也避免被测会话看见审计痕迹）。

设计约束（改动前先读）：
  1. **只降维、不判分。** 判据在预登记表里，不在脚本里。脚本能改判据 = 自造绿。
  2. **结构先勘察。** 输出固定含「节点类型清单」；与预期不符时先修本脚本的映射，
     不硬套（教训：查询类结论必须二次确认）。
  3. 只读源文件，不碰仓库、不改被测会话的产物。
#>
param(
	[Parameter(Mandatory = $true)][string]$InputFile,
	[string]$OutFile = '',
	[int]$PerMessage = 1200,
	[int]$ArgMax = 240,
	[switch]$TimelineOnly,
	[switch]$IncludeReasoning,
	[string[]]$Keywords = @('啰嗦', '冗余', '重复', '建议', '结论', '发现', '漏', '假绿', '误判')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InputFile)) { throw "not found: $InputFile" }
if ([string]::IsNullOrWhiteSpace($OutFile)) {
	$OutFile = [System.IO.Path]::ChangeExtension($InputFile, '.digest.txt')
}

# 显式 UTF-8 写出，绕开 Out-File / 重定向的编码坑（见 toolchain-win.md）
function Write-U8([string]$path, [string]$text) {
	[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}
function Trunc([string]$s, [int]$max) {
	if ([string]::IsNullOrEmpty($s)) { return '' }
	$s = $s -replace "`r", ''
	if ($s.Length -le $max) { return $s }
	$half = [int]($max / 2)
	return $s.Substring(0, $half) + "`n<<...省略 $($s.Length - $max) 字符...>>`n" + $s.Substring($s.Length - $half)
}

$raw = [System.IO.File]::ReadAllText($InputFile, [System.Text.Encoding]::UTF8)
$json = $raw | ConvertFrom-Json

$sb = New-Object System.Text.StringBuilder
function Emit([string]$s) { [void]$sb.AppendLine($s) }

Emit '================================================================'
Emit '会话导出 digest（由 tools/session-audit.ps1 生成，仅降维、不含判分）'
Emit '================================================================'
Emit "源文件   : $InputFile"
Emit "字符数   : $($raw.Length)"
Emit "schema   : $($json.schema) / v$($json.schemaVersion)"
Emit "导出时间 : $($json.exportedAt)"
Emit ''

# ---------------------------------------------------------------- 1. 结构勘察
Emit '## 1. 结构勘察（与预期不符就先修映射，不要硬套）'
Emit "顶层键   : $((($json.PSObject.Properties.Name) -join ', '))"
Emit "data 键  : $((($json.data.PSObject.Properties.Name) -join ', '))"
Emit ''

$idx = 0
$nodeTypes = @{}
$manifest = New-Object System.Collections.ArrayList
$calls = New-Object System.Collections.ArrayList
$bodies = New-Object System.Collections.ArrayList
$roles = @{}

foreach ($conv in $json.data.conversations) {
	foreach ($req in $conv.requests) {
		foreach ($m in $req.messages) {
			$idx++
			$role = [string]$m.role
			if ($roles.ContainsKey($role)) { $roles[$role]++ } else { $roles[$role] = 1 }
			$rawMsg = [string]$m.message

			$inner = $null
			try { $inner = $rawMsg | ConvertFrom-Json } catch { $inner = $null }
			if ($null -eq $inner) {
				[void]$manifest.Add(("{0}`t{1}`t{2}`t<<无法二次解析，原样保留前 120 字符>>`t{3}" -f $idx, $role, $rawMsg.Length, $rawMsg.Substring(0, [Math]::Min(120, $rawMsg.Length))))
				continue
			}

			$text = ''
			foreach ($c in $inner.content) {
				$t = [string]$c.type
				if ($nodeTypes.ContainsKey($t)) { $nodeTypes[$t]++ } else { $nodeTypes[$t] = 1 }
				switch ($t) {
					'text' { $text += [string]$c.text }
					'reasoning' { if ($IncludeReasoning) { $text += "[推理] " + [string]$c.text } }
					'tool-call' {
						$a = ''
						if ($c.PSObject.Properties['args']) { $a = ($c.args | ConvertTo-Json -Compress -Depth 6) }
						[void]$calls.Add(("{0}`t{1}`t{2}" -f $idx, $c.toolName, (Trunc $a $ArgMax)))
					}
					'tool-result' {
						$err = ''
						if ($c.PSObject.Properties['isError']) { $err = [string]$c.isError }
						[void]$calls.Add(("{0}`t<= {1}`tisError={2}" -f $idx, $c.toolName, $err))
					}
				}
			}

			$flat = ($text -replace "`r", ' ' -replace "`n", ' ')
			[void]$manifest.Add(("{0}`t{1}`t{2}`t{3}" -f $idx, $role, $rawMsg.Length, (Trunc $flat 160)))
			if ($text.Trim().Length -gt 0) {
				[void]$bodies.Add(("### [{0}] {1}`n{2}" -f $idx, $role, (Trunc $text $PerMessage)))
			}
		}
	}
}

Emit "消息总数 : $idx"
Emit "角色分布 : $(($roles.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
Emit "节点类型 : $(($nodeTypes.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
Emit ''

# ---------------------------------------------------------------- 2. 消息清单
Emit '## 2. 消息清单（序号 / 角色 / 原始长度 / 摘要）'
$manifest | ForEach-Object { Emit $_ }
Emit ''

# ---------------------------------------------------------------- 3. 工具时间线
Emit '## 3. 工具调用时间线（Runbook B 核心：声称 = 实做、顺序）'
if ($calls.Count -eq 0) { Emit '（本次导出没有 tool-call / tool-result 节点）' }
else { $calls | ForEach-Object { Emit $_ } }
Emit ''

# ---------------------------------------------------------------- 4. 锚点计数
Emit '## 4. 锚点命中次数（在原始 JSON 全文里数，含被转义的内容）'
function Count([string]$k) { return ([regex]::Matches($raw, [regex]::Escape($k))).Count }
Emit '-- 机制层（指针 / skill 是否被触及）--'
foreach ($k in @('AGENTS.md', 'godot-standards', 'process-audit', 'content-data-conventions', 'toolchain-win', 'CONTEXT.md', 'schema/README.md', 'audit-runbooks', 'use_skill', 'godot-4-7-verify', 'windows-chinese-io', 'cross-ticket-closeout', 'check-doc-links', 'pointer-audit-2026-09-06', '2026-09-06.md')) {
	Emit ("{0,5}  {1}" -f (Count $k), $k)
}
Emit '-- 机器层（是否真跑了）--'
foreach ($k in @('doc-links OK', 'SCRIPT ERROR', 'CHECK OK', 'run_battle_regression', 'check_project.gd', '--import', 'pre-commit', '--no-verify')) {
	Emit ("{0,5}  {1}" -f (Count $k), $k)
}
Emit '-- 纪律层（声称 = 实做）--'
foreach ($k in @('git commit', 'git add', 'git push', 'gh issue', 'gh issue comment', 'gh issue close', 'code-review', 'write_to_file', 'replace_in_file', 'Start-Process')) {
	Emit ("{0,5}  {1}" -f (Count $k), $k)
}
Emit ''

if (-not $TimelineOnly) {
	# ------------------------------------------------------------ 5. 关键词上下文
	Emit '## 5. 关键词上下文（每个词取首次出现处前后各 300 字符）'
	foreach ($k in $Keywords) {
		$m = [regex]::Match($raw, [regex]::Escape($k))
		if ($m.Success) {
			$start = [Math]::Max(0, $m.Index - 300)
			$len = [Math]::Min(600 + $k.Length, $raw.Length - $start)
			Emit "---- 关键词：$k （第 $($m.Index) 字符处）----"
			Emit (Trunc $raw.Substring($start, $len) 900)
		}
		else { Emit "---- 关键词：$k ：未命中----" }
	}
	Emit ''

	# ------------------------------------------------------------ 6. 对话正文
	Emit '## 6. 对话正文（text 节点；reasoning 默认不收，加 -IncludeReasoning 才收）'
	if ($bodies.Count -eq 0) { Emit '（无 text 节点）' }
	else { $bodies | ForEach-Object { Emit $_; Emit '' } }
}

Write-U8 $OutFile $sb.ToString()
Write-Output "digest written: $OutFile ($($sb.Length) chars)"
