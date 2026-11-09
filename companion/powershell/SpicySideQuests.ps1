<#
  Spicy Side Quests companion — PowerShell edition.

  Keeps a markdown todo file (e.g. an Obsidian note) and the Spicy Side Quests
  addon in sync. Needs nothing installed: works with the Windows PowerShell 5.1
  that ships with Windows 10/11, and with PowerShell 7 on any OS.

  Same behaviour, config and state files as the Node version (../src), so you
  can switch between them.

  Usage:
    powershell -ExecutionPolicy Bypass -File SpicySideQuests.ps1 [-Once] [-Setup] [-DryRun] [-Force] [-Config <file>]
  Or double-click start-powershell.cmd in the companion folder.
#>
[CmdletBinding()]
param(
  [switch]$Once,
  [switch]$Setup,
  [switch]$DryRun,
  [switch]$Force,
  [string]$Config,
  [switch]$Library # load functions only (used by the tests)
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

$script:VERSION = '0.1.0'
$script:ADDON = 'SpicySideQuests'
$script:DEFAULT_CATEGORY = 'General'
$script:Inv = [Globalization.CultureInfo]::InvariantCulture
$script:Rng = New-Object System.Random
$script:Utf8 = New-Object System.Text.UTF8Encoding $false

function New-Map { New-Object 'System.Collections.Generic.Dictionary[string,object]' }
# Safe dictionary lookup (works for Hashtable, Dictionary and ordered dictionaries; keeps arrays intact).
function Get-Key($d, [string]$k) {
  if ($null -eq $d) { return $null }
  $has = if ($d.PSObject.Methods['ContainsKey']) { $d.ContainsKey($k) } else { $d.Contains($k) }
  if (-not $has) { return $null }
  $v = $d[$k]
  if ($v -is [array]) { return , $v }
  return $v
}
function Get-Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Format-Num($n) { $d = [double]$n; if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return '0' }; $d.ToString('R', $script:Inv) }

# Same rule as Obsidian block IDs (and the addon): letters, digits and dashes.
function Test-ValidId($id) { ($id -is [string]) -and ($id -cmatch '^[A-Za-z0-9-]{1,64}$') }

# Single-line text: control characters and line separators become spaces.
function Get-OneLine([string]$s) { (($s -replace '[\x00-\x1f\x7f\u2028\u2029]', ' ') -replace ' {2,}', ' ').Trim() }

# Text that is safe to print to a terminal (no escape sequences).
function Get-TerminalSafe([string]$s) { $s -replace '[\x00-\x1f\x7f-\x9f]', '?' }
function Round1($v) { if ($null -eq $v) { $null } else { [math]::Round([double]$v * 10, [MidpointRounding]::AwayFromZero) / 10 } }

#region Lua --------------------------------------------------------------------
# Tiny reader/writer for Lua data files. Only reads literals, never runs code.

$script:ReSkip = [regex]'\G(?:\s+|--\[\[[\s\S]*?\]\]|--[^\n]*)*'
$script:ReIdent = [regex]'\G[A-Za-z_][A-Za-z0-9_]*'
$script:ReKeyIdent = [regex]'\G([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)'
$script:ReNum = [regex]'\G-?(?:0x[0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)'
$script:ReWord = [regex]'\G(?:true|false|nil)\b'
$script:ReDq = [regex]'\G"((?:[^"\\]|\\[\s\S])*)"'
$script:ReSq = [regex]"\G'((?:[^'\\]|\\[\s\S])*)'"
$script:ReLong = [regex]'\G\[(=*)\[([\s\S]*?)\]\1\]'
$script:ReEsc = [regex]'\\(\d{1,3}|[\s\S])'

function Read-LuaSkip { $script:LI += $script:ReSkip.Match($script:LS, $script:LI).Length }

function Read-LuaFail([string]$msg) {
  $line = ($script:LS.Substring(0, [math]::Min($script:LI, $script:LS.Length)) -split "`n").Count
  throw "Lua parse error on line ${line}: $msg"
}

function ConvertFrom-LuaEscapes([string]$s) {
  $script:ReEsc.Replace($s, [Text.RegularExpressions.MatchEvaluator] {
      param($m)
      $e = $m.Groups[1].Value
      switch -CaseSensitive ($e) {
        'n' { return "`n" } 't' { return "`t" } 'r' { return "`r" } 'a' { return [string][char]7 }
        'b' { return [string][char]8 } 'f' { return [string][char]12 } 'v' { return [string][char]11 }
        default {
          if ($e -match '^\d+$') { return [string][char][int]$e }
          return $e
        }
      }
    })
}

function Read-LuaValue {
  Read-LuaSkip
  if ($script:LI -ge $script:LS.Length) { Read-LuaFail 'unexpected end of file' }
  $ch = $script:LS[$script:LI]
  if ($ch -eq '{') { return , (Read-LuaTable) }
  foreach ($re in @($script:ReDq, $script:ReSq)) {
    $m = $re.Match($script:LS, $script:LI)
    if ($m.Success) { $script:LI += $m.Length; return (ConvertFrom-LuaEscapes $m.Groups[1].Value) }
  }
  $m = $script:ReLong.Match($script:LS, $script:LI)
  if ($m.Success) { $script:LI += $m.Length; return ($m.Groups[2].Value -replace '^\r?\n', '') }
  $m = $script:ReWord.Match($script:LS, $script:LI)
  if ($m.Success) {
    $script:LI += $m.Length
    if ($m.Value -eq 'nil') { return $null }
    return ($m.Value -eq 'true')
  }
  $m = $script:ReNum.Match($script:LS, $script:LI)
  if ($m.Success) {
    $script:LI += $m.Length
    $t = $m.Value
    if ($t -match '^(-?)0x(.+)$') { return [double]([Convert]::ToInt64($Matches[2], 16)) * $(if ($Matches[1]) { -1 } else { 1 }) }
    return [double]::Parse($t, $script:Inv)
  }
  Read-LuaFail "unexpected '$ch'"
}

function Read-LuaTable {
  $script:LI++ # {
  $script:LDepth++
  if ($script:LDepth -gt 32) { Read-LuaFail 'tables nested too deeply' }
  $keyed = New-Map
  $list = New-Object 'System.Collections.Generic.List[object]'
  $hasKeys = $false
  while ($true) {
    Read-LuaSkip
    if ($script:LI -ge $script:LS.Length) { Read-LuaFail 'unterminated table' }
    $ch = $script:LS[$script:LI]
    if ($ch -eq '}') { $script:LI++; break }
    $key = $null
    if ($ch -eq '[' -and -not $script:ReLong.Match($script:LS, $script:LI).Success) {
      $script:LI++
      $key = Read-LuaValue
      Read-LuaSkip
      if ($script:LS[$script:LI] -ne ']') { Read-LuaFail "expected ']'" }
      $script:LI++
      Read-LuaSkip
      if ($script:LS[$script:LI] -ne '=') { Read-LuaFail "expected '='" }
      $script:LI++
    }
    else {
      $m = $script:ReKeyIdent.Match($script:LS, $script:LI)
      if ($m.Success -and $m.Groups[1].Value -notin @('true', 'false', 'nil')) {
        $key = $m.Groups[1].Value
        $script:LI += $m.Length
      }
    }
    $v = Read-LuaValue
    if ($null -eq $key) { $list.Add($v) }
    elseif ($key -is [double] -and $key -ge 1 -and $key -eq [math]::Floor($key)) {
      while ($list.Count -lt $key) { $list.Add($null) }
      $list[[int]$key - 1] = $v
    }
    else { $keyed[[string]$key] = $v; $hasKeys = $true }
    Read-LuaSkip
    if ($script:LI -lt $script:LS.Length -and ($script:LS[$script:LI] -eq ',' -or $script:LS[$script:LI] -eq ';')) { $script:LI++ }
  }
  $script:LDepth--
  if (-not $hasKeys) { return , $list.ToArray() }
  for ($n = 0; $n -lt $list.Count; $n++) { $keyed[[string]($n + 1)] = $list[$n] }
  return , $keyed
}

# Parses `Name = value` assignments, e.g. a SavedVariables file.
function Read-LuaAssignments([string]$Src) {
  $script:LS = $Src
  $script:LI = 0
  $script:LDepth = 0
  $out = New-Map
  Read-LuaSkip
  while ($script:LI -lt $script:LS.Length) {
    $m = $script:ReIdent.Match($script:LS, $script:LI)
    if (-not $m.Success) { Read-LuaFail 'expected identifier' }
    $script:LI += $m.Length
    Read-LuaSkip
    if ($script:LS[$script:LI] -ne '=') { Read-LuaFail "expected '='" }
    $script:LI++
    $out[$m.Value] = Read-LuaValue
    Read-LuaSkip
    if ($script:LI -lt $script:LS.Length -and $script:LS[$script:LI] -eq ';') { $script:LI++; Read-LuaSkip }
  }
  return , $out
}

function Format-LuaString([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($c in $s.ToCharArray()) {
    $code = [int]$c
    if ($c -eq '\') { [void]$sb.Append('\\') }
    elseif ($c -eq '"') { [void]$sb.Append('\"') }
    elseif ($c -eq "`n") { [void]$sb.Append('\n') }
    elseif ($c -eq "`r") { [void]$sb.Append('\r') }
    elseif ($c -eq "`t") { [void]$sb.Append('\t') }
    elseif ($code -lt 32 -or $code -eq 127) { [void]$sb.Append('\' + $code.ToString('000')) }
    else { [void]$sb.Append($c) }
  }
  [void]$sb.Append('"')
  $sb.ToString()
}

function ConvertTo-Lua($v, [string]$indent = '') {
  if ($null -eq $v) { return 'nil' }
  if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
  if ($v -is [string]) { return (Format-LuaString $v) }
  if ($v -is [ValueType]) { return (Format-Num $v) }
  $inner = $indent + "`t"
  if ($v -is [Collections.IDictionary]) {
    $parts = foreach ($k in @($v.Keys)) {
      if ($null -eq $v[$k]) { continue }
      $key = if ($k -match '^[A-Za-z_][A-Za-z0-9_]*$') { $k } else { '[' + (Format-LuaString $k) + ']' }
      "$inner$key = $(ConvertTo-Lua $v[$k] $inner),`n"
    }
    if (-not $parts) { return '{}' }
    return "{`n" + (-join $parts) + "$indent}"
  }
  $arr = @($v)
  if ($arr.Count -eq 0) { return '{}' }
  $parts = foreach ($x in $arr) { "$inner$(ConvertTo-Lua $x $inner),`n" }
  return "{`n" + (-join $parts) + "$indent}"
}
#endregion

#region Items ------------------------------------------------------------------
function Get-Tags($t) { if ($null -eq $t) { return , @() } return , @($t | Where-Object { $_ -is [string] }) }

function New-TodoItem($src) {
  # Normalises any dictionary / object into the item shape.
  $g = { param($k) if ($src -is [Collections.IDictionary]) { Get-Key $src $k } else { $p = $src.PSObject.Properties[$k]; if ($p) { , $p.Value } else { $null } } }
  $num = { param($v) if ($v -is [ValueType] -and $v -isnot [bool]) { [double]$v } else { $null } }
  $str = { param($v) if ($v -is [string]) { $v } else { $null } }
  $cat = & $str (& $g 'category')
  @{
    id       = [string](& $g 'id')
    text     = [string](& $g 'text')
    tags     = (Get-Tags (& $g 'tags'))
    category = $(if ($cat) { $cat } else { $script:DEFAULT_CATEGORY })
    done     = ((& $g 'done') -eq $true)
    deleted  = $(if ((& $g 'deleted') -eq $true) { $true } else { $null })
    zone     = (& $str (& $g 'zone'))
    mapID    = (& $num (& $g 'mapID'))
    x        = (& $num (& $g 'x'))
    y        = (& $num (& $g 'y'))
    created  = $(if ($null -ne (& $num (& $g 'created'))) { & $num (& $g 'created') } else { 0 })
    updated  = $(if ($null -ne (& $num (& $g 'updated'))) { & $num (& $g 'updated') } else { 0 })
  }
}

function Copy-TodoItem($i) { $n = @{}; foreach ($k in @($i.Keys)) { $n[$k] = $i[$k] }; $n }

# True when two items have the same user-visible content.
function Test-SameContent($a, $b) {
  ($a.text -ceq $b.text) -and
  ([bool]$a.done -eq [bool]$b.done) -and
  ([bool]$a.deleted -eq [bool]$b.deleted) -and
  ($a.category.ToLowerInvariant() -ceq $b.category.ToLowerInvariant()) -and
  ((@($a.tags) -join ' ').ToLowerInvariant() -ceq (@($b.tags) -join ' ').ToLowerInvariant()) -and
  ([string]$a.zone -ceq [string]$b.zone) -and
  ((Round1 $a.x) -eq (Round1 $b.x)) -and
  ((Round1 $a.y) -eq (Round1 $b.y))
}

# Ordered, null-free copy for JSON/Lua output (matches the Node version's files).
function ConvertTo-ItemOutput($i) {
  $o = [ordered]@{}
  foreach ($k in 'id', 'text', 'tags', 'category', 'done', 'deleted', 'zone', 'mapID', 'x', 'y', 'created', 'updated') {
    if ($null -ne $i[$k]) { $o[$k] = $i[$k] }
  }
  $o.tags = @($i.tags)
  $o
}
#endregion

#region Markdown ---------------------------------------------------------------
$script:ReTask = [regex]'^([-*+]) \[(.)\] (.*)$'
$script:ReHeading = [regex]'^#{2,6}[ \t]+(.*)$'
$script:ReHeadingClose = [regex]'(?:^|[ \t])#+$'
# Lines longer than this are kept as plain text and never parsed (guards against pathological input).
$script:MAX_LINE = 1000
$script:ReFence = [regex]'^\s*(```|~~~)'
$script:ReBlockId = [regex]'\s+\^([A-Za-z0-9-]+)\s*$'
$script:ReZone = [regex]'(?i)\[zone::([^\]]*)\]'
$script:ReXY = [regex]'(?i)\[xy::\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*\]'
$script:ReTag = [regex]'(^|\s)#([\p{L}\p{N}_/-]+)'

function Read-TaskText([string]$body) {
  $rest = $body
  $id = $null; $zone = $null; $x = $null; $y = $null
  $m = $script:ReBlockId.Match($rest)
  if ($m.Success) { $id = $m.Groups[1].Value; $rest = $rest.Substring(0, $m.Index) }
  $m = $script:ReZone.Match($rest)
  if ($m.Success) { if ($m.Groups[1].Value.Trim()) { $zone = $m.Groups[1].Value.Trim() }; $rest = $script:ReZone.Replace($rest, ' ', 1) }
  $m = $script:ReXY.Match($rest)
  if ($m.Success) {
    $x = [double]::Parse($m.Groups[1].Value, $script:Inv); $y = [double]::Parse($m.Groups[2].Value, $script:Inv)
    $rest = $script:ReXY.Replace($rest, ' ', 1)
  }
  $tags = New-Object 'System.Collections.Generic.List[string]'
  $rest = $script:ReTag.Replace($rest, [Text.RegularExpressions.MatchEvaluator] {
      param($mm)
      $tag = $mm.Groups[2].Value
      if ($tag -notmatch '\p{L}') { return $mm.Value } # "#1" is not a tag in Obsidian
      $dupe = $false
      foreach ($t in $tags) { if ($t.ToLowerInvariant() -ceq $tag.ToLowerInvariant()) { $dupe = $true } }
      if (-not $dupe) { $tags.Add($tag) }
      return $mm.Groups[1].Value
    })
  @{ id = $id; text = ($rest -replace '\s+', ' ').Trim(); tags = $tags.ToArray(); zone = $zone; x = $x; y = $y }
}

function Read-Markdown([string]$src) {
  $eol = if ($src.Contains("`r`n")) { "`r`n" } else { "`n" }
  $raw = $src -split "\r?\n"
  $lines = New-Object 'System.Collections.Generic.List[object]'
  $category = $script:DEFAULT_CATEGORY
  $inFence = $false
  $inFront = ($raw.Count -gt 0 -and $raw[0] -eq '---')
  for ($idx = 0; $idx -lt $raw.Count; $idx++) {
    $line = $raw[$idx]
    if ($inFront) {
      $lines.Add(@{ kind = 'text'; raw = $line })
      if ($idx -gt 0 -and $line -eq '---') { $inFront = $false }
      continue
    }
    $isFence = $script:ReFence.IsMatch($line)
    if ($isFence) { $inFence = -not $inFence }
    if ($line.Length -gt $script:MAX_LINE) { $lines.Add(@{ kind = 'text'; raw = $line }); continue }
    if ($inFence -or $isFence) { $lines.Add(@{ kind = 'text'; raw = $line }); continue }
    $h = $script:ReHeading.Match($line)
    if ($h.Success -and $h.Groups[1].Value.Trim()) {
      $category = $script:ReHeadingClose.Replace($h.Groups[1].Value.TrimEnd(), '').Trim()
      if (-not $category) { $category = $script:DEFAULT_CATEGORY }
      $lines.Add(@{ kind = 'heading'; raw = $line; category = $category })
      continue
    }
    $t = $script:ReTask.Match($line)
    if ($t.Success) {
      $p = Read-TaskText $t.Groups[3].Value
      if ($p.text -ne '') {
        $p.category = $category
        $p.done = ($t.Groups[2].Value -ne ' ')
        $lines.Add(@{ kind = 'item'; raw = $line; item = $p })
        continue
      }
    }
    $lines.Add(@{ kind = 'text'; raw = $line })
  }
  @{ lines = $lines; eol = $eol }
}

function Get-MdItems($doc) {
  $out = New-Object 'System.Collections.Generic.List[object]'
  foreach ($l in $doc.lines) { if ($l.kind -eq 'item') { $out.Add($l.item) } }
  return , $out
}

# Values written into the file are reduced to one safe line each, so data from the
# game can never add extra lines, headings or todos to your notes.
function Get-CleanCategory([string]$c) { $v = (Get-OneLine $c) -replace '^#+\s*', ''; if ($v) { $v } else { $script:DEFAULT_CATEGORY } }

function Format-TodoLine($item) {
  $parts = New-Object 'System.Collections.Generic.List[string]'
  $text = Get-OneLine ([string]$item.text)
  $parts.Add($(if ($text) { $text } else { '(untitled)' }))
  foreach ($t in @($item.tags)) { $ct = ([string]$t) -replace '[^\p{L}\p{N}_/-]', ''; if ($ct -match '\p{L}') { $parts.Add('#' + $ct) } }
  $zone = if ($item.zone) { (Get-OneLine ([string]$item.zone)) -replace '[\[\]]', '' } else { '' }
  if ($zone) { $parts.Add("[zone:: $zone]") }
  if ($null -ne $item.x -and $null -ne $item.y) { $parts.Add("[xy:: $(Format-Num (Round1 $item.x)), $(Format-Num (Round1 $item.y))]") }
  $parts.Add('^' + $item.id)
  $box = if ($item.done) { 'x' } else { ' ' }
  "- [$box] $($parts -join ' ')"
}

# Converts a parsed markdown item into a full item, borrowing id/timestamps from $ref.
function ConvertTo-TodoItem($md, [string]$id, $ref) {
  $mapID = $null
  if ($md.zone -and $null -ne $ref -and $ref.zone -ceq $md.zone) { $mapID = $ref.mapID }
  @{
    id = $id; text = $md.text; tags = @($md.tags); category = $md.category; done = [bool]$md.done
    deleted = $null; zone = $md.zone; mapID = $mapID; x = $md.x; y = $md.y
    created = $(if ($null -ne $ref) { $ref.created } else { 0 }); updated = $(if ($null -ne $ref) { $ref.updated } else { 0 })
  }
}

# Re-renders the document: unchanged lines stay byte for byte, deleted items are
# removed, new/moved items go to the end of their section (created if missing).
function Format-Markdown($doc, $items) {
  $byId = New-Map
  foreach ($i in $items) { if (-not $i.deleted) { $byId[$i.id] = $i } }
  $sections = New-Object 'System.Collections.Generic.List[object]'
  $sections.Add(@{ category = $script:DEFAULT_CATEGORY; out = (New-Object 'System.Collections.Generic.List[string]'); lastItem = -1; headed = $false })
  $placed = New-Object 'System.Collections.Generic.HashSet[string]'

  foreach ($line in $doc.lines) {
    $sec = $sections[$sections.Count - 1]
    if ($line.kind -eq 'heading') {
      $o = New-Object 'System.Collections.Generic.List[string]'; $o.Add($line.raw)
      $sections.Add(@{ category = $line.category; out = $o; lastItem = 0; headed = $true })
      continue
    }
    if ($line.kind -eq 'item') {
      $id = $line.item.id
      $final = if ($id) { Get-Key $byId $id } else { $null }
      if ($null -eq $final -or $final.category.ToLowerInvariant() -cne $sec.category.ToLowerInvariant() -or $placed.Contains($final.id)) { continue }
      $asMd = ConvertTo-TodoItem $line.item $final.id $final
      $m = $script:ReBlockId.Match($line.raw)
      $keepRaw = (Test-SameContent $asMd $final) -and $m.Success -and ($m.Groups[1].Value -ceq $final.id)
      $sec.out.Add($(if ($keepRaw) { $line.raw } else { Format-TodoLine $final }))
      $sec.lastItem = $sec.out.Count - 1
      [void]$placed.Add($final.id)
      continue
    }
    $sec.out.Add($line.raw)
  }

  foreach ($item in $items) {
    if ($item.deleted -or $placed.Contains($item.id)) { continue }
    $target = $null
    foreach ($s in $sections) { if ($s.headed -and $s.category.ToLowerInvariant() -ceq $item.category.ToLowerInvariant()) { $target = $s; break } }
    if ($null -eq $target -and $sections.Count -eq 1 -and $item.category.ToLowerInvariant() -ceq $script:DEFAULT_CATEGORY.ToLowerInvariant()) { $target = $sections[0] }
    if ($null -eq $target) {
      $last = $sections[$sections.Count - 1].out
      while ($last.Count -gt 0 -and $last[$last.Count - 1].Trim() -eq '') { $last.RemoveAt($last.Count - 1) }
      if ($last.Count -gt 0) { $last.Add('') }
      $o = New-Object 'System.Collections.Generic.List[string]'; $o.Add("## $(Get-CleanCategory $item.category)")
      $target = @{ category = $item.category; out = $o; lastItem = 0; headed = $true }
      $sections.Add($target)
    }
    $at = if ($target.lastItem -ge 0) { $target.lastItem + 1 } else { $target.out.Count }
    $target.out.Insert($at, (Format-TodoLine $item))
    $target.lastItem = $at
  }

  $all = New-Object 'System.Collections.Generic.List[string]'
  foreach ($s in $sections) { $all.AddRange($s.out) }
  if ($all.Count -gt 0 -and $all[$all.Count - 1] -ne '') { $all.Add('') }
  $all -join $doc.eol
}
#endregion

#region Merge ------------------------------------------------------------------
# Three-way merge between markdown, game and the last synced state.
# When both sides changed the same item, the most recent change wins.
function Merge-Todos {
  param($Base, $Md, [double]$MdTime, $Game, $GameOrder, [double]$TombstoneDays = 30)
  $log = New-Object 'System.Collections.Generic.List[string]'
  $taken = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($k in @($Base.Keys) + @($Game.Keys)) { [void]$taken.Add($k) }

  $mdMap = New-Map
  $order = New-Object 'System.Collections.Generic.List[string]'
  foreach ($item in $Md) {
    if (-not $item.id -or $mdMap.ContainsKey($item.id)) { $item.id = New-TodoId $taken }
    [void]$taken.Add($item.id)
    $mdMap[$item.id] = $item
  }
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  $push = { param($id) if ($seen.Add($id)) { $order.Add($id) } }
  foreach ($id in @($mdMap.Keys)) { & $push $id }
  foreach ($id in @($GameOrder)) { if ($id -and $Game.ContainsKey($id)) { & $push $id } }
  foreach ($id in @($Game.Keys)) { & $push $id }
  foreach ($id in @($Base.Keys)) { & $push $id }

  $items = New-Object 'System.Collections.Generic.List[object]'
  foreach ($id in $order) {
    $b = Get-Key $Base $id; $g = Get-Key $Game $id; $m = Get-Key $mdMap $id
    $fromMd = $null
    if ($null -ne $m) {
      $ref = if ($null -ne $b) { $b } else { $g }
      $asItem = ConvertTo-TodoItem $m $id $ref
      if ($null -eq $ref) { $asItem.created = $MdTime; $asItem.updated = $MdTime }
      $changed = if ($null -ne $b) { [bool]$b.deleted -or -not (Test-SameContent $asItem $b) } else { -not ($null -ne $g -and (Test-SameContent $asItem $g)) }
      if ($changed) {
        $prev = if ($null -ne $b) { $b.updated } else { 0 }
        $asItem.updated = [math]::Max($MdTime, $prev + 1)
        $fromMd = $asItem
      }
    }
    elseif ($null -ne $b -and -not $b.deleted) {
      $fromMd = Copy-TodoItem $b
      $fromMd.deleted = $true
      $fromMd.updated = [math]::Max($MdTime, $b.updated + 1)
    }
    $fromGame = if ($null -ne $g -and ($null -eq $b -or $g.updated -gt $b.updated)) { $g } else { $null }

    $final = $null; $source = ''
    if ($null -ne $fromMd -and $null -ne $fromGame) {
      if ($fromGame.updated -gt $fromMd.updated) { $final = $fromGame; $source = 'game' } else { $final = $fromMd; $source = 'markdown' }
    }
    elseif ($null -ne $fromMd) { $final = $fromMd; $source = 'markdown' }
    elseif ($null -ne $fromGame) { $final = $fromGame; $source = 'game' }
    elseif ($null -ne $b) { $final = $b }
    else { $final = $g }
    if ($null -eq $final) { continue }
    if ($source) { $d = Get-ChangeText $b $final $source; if ($d) { $log.Add($d) } }
    $items.Add($final)
  }

  $cutoff = (Get-Now) - $TombstoneDays * 86400
  $kept = New-Object 'System.Collections.Generic.List[object]'
  foreach ($i in $items) { if (-not ($i.deleted -and $i.updated -lt $cutoff)) { $kept.Add($i) } }
  @{ items = $kept; log = $log }
}

function Get-ChangeText($prev, $next, [string]$source) {
  $arrow = if ($source -eq 'game') { 'game -> markdown' } else { 'markdown -> game' }
  $name = '"' + $next.text + '"'
  if ($next.deleted) { if ($null -ne $prev -and -not $prev.deleted) { return "${arrow}: removed $name" } return '' }
  if ($null -eq $prev -or $prev.deleted) { return "${arrow}: added $name ($($next.category))" }
  if ([bool]$prev.done -ne [bool]$next.done) { return "${arrow}: $(if ($next.done) { 'completed' } else { 'reopened' }) $name" }
  if (Test-SameContent $prev $next) { return '' }
  "${arrow}: updated $name"
}

function New-TodoId($taken) {
  $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
  while ($true) {
    $id = -join (1..6 | ForEach-Object { $chars[$script:Rng.Next($chars.Length)] })
    if (-not $taken.Contains($id)) { return $id }
  }
}
#endregion

#region Files, config & sync ---------------------------------------------------
function Join-Paths { [IO.Path]::Combine([string[]]$args) }

function Get-DefaultConfigDir {
  if ($env:APPDATA) { return (Join-Paths $env:APPDATA $script:ADDON) }
  $xdg = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Paths $HOME '.config' }
  Join-Paths $xdg 'spicysidequests'
}

# Copies settings from the old "WoW Todo Sync" name, once.
function Move-OldConfigDir([string]$newDir) {
  if (Test-Path -LiteralPath $newDir) { return $false }
  $old = if ($env:APPDATA) { Join-Paths $env:APPDATA 'WoWTodoSync' } else { Join-Paths $(if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Paths $HOME '.config' }) 'wowtodosync' }
  if (-not (Test-Path -LiteralPath $old)) { return $false }
  Copy-Item -LiteralPath $old -Destination $newDir -Recurse
  $true
}

function Get-CleanPath([string]$p) {
  $s = $p.Trim().Trim('"', "'")
  if ($s.StartsWith('~')) { $s = $HOME + $s.Substring(1) }
  if ($s) { $s = [IO.Path]::GetFullPath($s) }
  $s
}

function Get-AddonDir([string]$wow) { Join-Paths $wow 'Interface' 'AddOns' $script:ADDON }
function Test-AddonInstalled([string]$wow) { $wow -and (Test-Path -LiteralPath (Join-Paths (Get-AddonDir $wow) "$($script:ADDON).toc")) }

function Write-FileAtomic([string]$file, [string]$content) {
  $dir = Split-Path -Parent $file
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
  # Random, exclusive temp name: never follows a pre-existing file or symlink.
  $tmp = "$file.$([guid]::NewGuid().ToString('N').Substring(0, 12)).tmp"
  $bytes = $script:Utf8.GetBytes($content)
  $fs = New-Object IO.FileStream($tmp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
  try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
  try {
    if (Test-Path -LiteralPath $file) { [IO.File]::Replace($tmp, $file, [NullString]::Value) } else { [IO.File]::Move($tmp, $file) }
  }
  catch {
    [IO.File]::WriteAllText($file, $content, $script:Utf8) # e.g. locked on Windows
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Read-Config([string]$file) {
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  $raw = [IO.File]::ReadAllText($file) | ConvertFrom-Json
  $poll = 2
  if ($raw.PSObject.Properties['pollSeconds'] -and [double]$raw.pollSeconds -gt 0) { $poll = [double]$raw.pollSeconds }
  $acct = 'auto'
  if ($raw.PSObject.Properties['account'] -and $raw.account) { $acct = [string]$raw.account }
  @{
    todoFile = $(if ($raw.PSObject.Properties['todoFile']) { Get-CleanPath ([string]$raw.todoFile) } else { '' })
    wowPath = $(if ($raw.PSObject.Properties['wowPath']) { Get-CleanPath ([string]$raw.wowPath) } else { '' })
    account = $acct; pollSeconds = $poll
  }
}

function Save-Config([string]$file, $cfg) {
  $o = [ordered]@{ todoFile = $cfg.todoFile; wowPath = $cfg.wowPath; account = $cfg.account; pollSeconds = $cfg.pollSeconds }
  Write-FileAtomic $file (($o | ConvertTo-Json) + "`n")
}

function Find-WowPaths {
  $roots = @()
  foreach ($d in 'C:', 'D:', 'E:') {
    $roots += "$d\Program Files (x86)\World of Warcraft", "$d\Program Files\World of Warcraft", "$d\World of Warcraft", "$d\Games\World of Warcraft"
  }
  $found = @()
  foreach ($r in $roots) { foreach ($f in '_forever_', '_forever_beta_', '_classic_beta_') { $p = Join-Paths $r $f; if (Test-AddonInstalled $p) { $found += $p } } }
  , $found
}

function Invoke-Setup([string]$file, $existing) {
  Write-Host "`nSpicy Side Quests setup - settings are saved to $file`n"
  $ask = { param($q, $def) $a = (Read-Host $(if ($def) { "$q`n  [$def]" } else { $q })).Trim(); if ($a) { $a } else { $def } }
  $todo = ''
  while (-not $todo) {
    $todo = Get-CleanPath ([string](& $ask 'Path to your markdown todo file (it will be created if missing)' $(if ($existing) { $existing.todoFile } else { '' })))
    if (-not $todo.ToLowerInvariant().EndsWith('.md')) { Write-Host '  Please give a .md file.'; $todo = '' }
  }
  $detected = Find-WowPaths
  $wow = ''
  while (-not $wow) {
    $def = if ($existing -and $existing.wowPath) { $existing.wowPath } elseif ($detected.Count) { $detected[0] } else { '' }
    $wow = Get-CleanPath ([string](& $ask 'WoW Forever folder (the one that contains Interface and WTF)' $def))
    if (-not (Test-AddonInstalled $wow)) {
      Write-Host "  Couldn't find $(Join-Paths (Get-AddonDir $wow) "$($script:ADDON).toc")."
      if ((& $ask '  Use this folder anyway? (y/N)' 'n') -ne 'y') { $wow = '' }
    }
  }
  $cfg = @{ todoFile = $todo; wowPath = $wow; account = $(if ($existing) { $existing.account } else { 'auto' }); pollSeconds = $(if ($existing) { $existing.pollSeconds } else { 2 }) }
  Save-Config $file $cfg
  Write-Host "`nSaved. Run again with -Setup to change these.`n"
  $cfg
}

function Find-SavedVariables($cfg) {
  $accRoot = Join-Paths $cfg.wowPath 'WTF' 'Account'
  if ($cfg.account -and $cfg.account -ne 'auto') { return (Join-Paths $accRoot $cfg.account 'SavedVariables' "$($script:ADDON).lua") }
  if (-not (Test-Path -LiteralPath $accRoot)) { return $null }
  $files = foreach ($d in (Get-ChildItem -LiteralPath $accRoot -Directory)) {
    $f = Join-Paths $d.FullName 'SavedVariables' "$($script:ADDON).lua"
    if (Test-Path -LiteralPath $f) { Get-Item -LiteralPath $f }
  }
  $newest = @($files) | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($newest) { $newest.FullName } else { $null }
}

function Read-GameData([string]$svFile) {
  $res = @{ items = (New-Map); order = @(); categories = @() }
  if (-not $svFile -or -not (Test-Path -LiteralPath $svFile)) { return $res }
  $all = Read-LuaAssignments ([IO.File]::ReadAllText($svFile))
  $db = Get-Key $all 'SpicySideQuestsDB'
  if ($db -isnot [Collections.IDictionary]) { return $res }
  $items = Get-Key $db 'items'
  if ($items -is [Collections.IDictionary]) {
    foreach ($v in @($items.Values)) {
      if ($v -isnot [Collections.IDictionary]) { continue }
      $id = Get-Key $v 'id'; $text = Get-Key $v 'text'
      if (-not (Test-ValidId $id) -or $text -isnot [string] -or $res.items.ContainsKey($id)) { continue }
      $item = New-TodoItem $v
      $item.text = Get-OneLine $item.text
      $item.category = Get-CleanCategory $item.category
      $res.items[$id] = $item
    }
  }
  foreach ($k in 'order', 'categories') {
    $list = Get-Key $db $k
    if ($list -is [array]) { $res[$k] = @($list | Where-Object { $_ -is [string] }) }
  }
  $res
}

function Read-State([string]$file) {
  $base = New-Map
  if (Test-Path -LiteralPath $file) {
    try {
      $s = [IO.File]::ReadAllText($file) | ConvertFrom-Json
      if ($s.PSObject.Properties['base'] -and $s.base) {
        foreach ($p in $s.base.PSObject.Properties) {
          if ((Test-ValidId $p.Name) -and $p.Value -and $p.Value.PSObject.Properties['text']) { $base[$p.Name] = New-TodoItem $p.Value; $base[$p.Name].id = $p.Name }
        }
      }
    }
    catch { }
  }
  @{ base = $base }
}

function Save-State([string]$file, $state) {
  $o = [ordered]@{}
  foreach ($k in @($state.base.Keys)) { $o[$k] = ConvertTo-ItemOutput $state.base[$k] }
  Write-FileAtomic $file ((@{ base = $o } | ConvertTo-Json -Depth 6) + "`n")
}

function Get-Sha1([string]$s) {
  $sha = [Security.Cryptography.SHA1]::Create()
  -join ($sha.ComputeHash($script:Utf8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') })
}

function Format-Inbox($items, $categories, [double]$generated, [string]$hash) {
  $payload = [ordered]@{ generated = $generated; categories = @($categories); items = @($items | ForEach-Object { ConvertTo-ItemOutput $_ }) }
  "-- Written by the Spicy Side Quests companion app. Changes here are overwritten.`n" +
  "-- Without the companion app this file stays empty and the addon works in-game only.`n" +
  "-- hash: $hash`n" +
  "SpicySideQuests_Inbox = $(ConvertTo-Lua $payload)`n"
}

$script:NEW_FILE = "---`ntags: [wow, todo]`n---`n`n# WoW Todo`n`nSynced with the Spicy Side Quests addon. Use ``## Headings`` for categories.`n`n## $($script:DEFAULT_CATEGORY)`n"

# One sync pass. Returns the new state, or $null when it skipped for safety.
function Invoke-SyncOnce($cfg, $state, [switch]$DryRun, [switch]$Force, [scriptblock]$Log, [scriptblock]$Warn) {
  $liveBase = @($state.base.Values | Where-Object { -not $_.deleted }).Count
  if (Test-Path -LiteralPath $cfg.todoFile) {
    $mdSrc = [IO.File]::ReadAllText($cfg.todoFile)
    $mdTime = [DateTimeOffset]::new((Get-Item -LiteralPath $cfg.todoFile).LastWriteTimeUtc).ToUnixTimeSeconds()
  }
  elseif ($liveBase -eq 0) {
    $mdSrc = $script:NEW_FILE; $mdTime = Get-Now
    & $Log "Creating $($cfg.todoFile)"
  }
  else {
    & $Warn "Markdown file not found: $($cfg.todoFile) - skipping so nothing gets deleted."
    return $null
  }
  $doc = Read-Markdown $mdSrc
  $md = Get-MdItems $doc
  if ($md.Count -eq 0 -and $liveBase -gt 0 -and -not $Force) {
    & $Warn "The markdown file has no todos but $liveBase were synced before. Skipping so nothing gets deleted (use -Force to accept)."
    return $null
  }

  $game = Read-GameData (Find-SavedVariables $cfg)
  $result = Merge-Todos -Base $state.base -Md $md -MdTime $mdTime -Game $game.items -GameOrder $game.order
  foreach ($l in $result.log) { & $Log $l }

  $newMd = Format-Markdown $doc $result.items
  if (($newMd -cne $mdSrc -or -not (Test-Path -LiteralPath $cfg.todoFile)) -and -not $DryRun) { Write-FileAtomic $cfg.todoFile $newMd }

  $cats = New-Object 'System.Collections.Generic.List[string]'
  $addCat = { param($c) foreach ($x in $cats) { if ($x.ToLowerInvariant() -ceq $c.ToLowerInvariant()) { return } }; $cats.Add($c) }
  foreach ($l in $doc.lines) {
    if ($l.kind -eq 'heading') { foreach ($i in $result.items) { if ($i.category.ToLowerInvariant() -ceq $l.category.ToLowerInvariant()) { & $addCat $l.category; break } } }
  }
  foreach ($c in $game.categories) { & $addCat $c }
  foreach ($i in $result.items) { & $addCat $i.category }

  # Compared against the file itself, so an addon update that resets Inbox.lua gets rewritten.
  $hash = Get-Sha1 (Format-Inbox $result.items $cats 0 '')
  $inboxFile = Join-Paths (Get-AddonDir $cfg.wowPath) 'Inbox.lua'
  $current = if (Test-Path -LiteralPath $inboxFile) { [IO.File]::ReadAllText($inboxFile) } else { '' }
  if (-not $current.Contains("-- hash: $hash`n")) {
    if (-not $DryRun) { Write-FileAtomic $inboxFile (Format-Inbox $result.items $cats (Get-Now) $hash) }
    if (@($result.log | Where-Object { $_.StartsWith('markdown') }).Count) { & $Log 'Type /reload in game to see markdown changes.' }
  }

  $base = New-Map
  foreach ($i in $result.items) { $base[$i.id] = $i }
  @{ base = $base }
}
#endregion

if ($Library) { return }

#region Main -------------------------------------------------------------------
# Messages can contain todo text, so strip terminal escape sequences before printing.
$logFn = { param($m) Write-Host "$(Get-Date -Format 'HH:mm:ss') " -ForegroundColor DarkGray -NoNewline; Write-Host (Get-TerminalSafe $m) }
$warnFn = { param($m) Write-Host "$(Get-Date -Format 'HH:mm:ss') " -ForegroundColor DarkGray -NoNewline; Write-Host (Get-TerminalSafe $m) -ForegroundColor Yellow }

if (-not $Config -and (Move-OldConfigDir (Get-DefaultConfigDir))) { & $logFn "Copied your settings from the old WoW Todo Sync folder to $(Get-DefaultConfigDir)" }
$configFile = if ($Config) { Get-CleanPath $Config } else { Join-Paths (Get-DefaultConfigDir) 'config.json' }
$stateFile = Join-Paths (Split-Path -Parent $configFile) 'state.json'

$cfg = Read-Config $configFile
if ($null -eq $cfg -or $Setup -or -not $cfg.todoFile -or -not $cfg.wowPath) { $cfg = Invoke-Setup $configFile $cfg }

Write-Host "Spicy Side Quests v$($script:VERSION) (PowerShell)$(if ($DryRun) { '  (dry run)' })"
Write-Host "  markdown: $($cfg.todoFile)"
Write-Host "  game:     $($cfg.wowPath)"
if (-not (Test-AddonInstalled $cfg.wowPath)) { & $warnFn "The addon isn't installed in that WoW folder yet." }
$sv = Find-SavedVariables $cfg
Write-Host "  saved:    $(if ($sv) { $sv } else { '(not found yet - log in once with the addon enabled)' })`n"

$state = Read-State $stateFile

function Invoke-Pass {
  $next = Invoke-SyncOnce $cfg $script:state -DryRun:$DryRun -Force:$Force -Log $logFn -Warn $warnFn
  if ($null -ne $next) {
    $script:state = $next
    if (-not $DryRun) { Save-State $stateFile $next }
  }
}

function Get-Signature {
  $parts = foreach ($f in @($cfg.todoFile, (Find-SavedVariables $cfg))) {
    if ($f -and (Test-Path -LiteralPath $f)) { $i = Get-Item -LiteralPath $f; "$($i.LastWriteTimeUtc.Ticks):$($i.Length)" } else { '-' }
  }
  $parts -join '|'
}

if ($Once) {
  Invoke-Pass
  & $logFn 'Done.'
  return
}

$lastSig = ''; $lastError = ''
& $logFn "Watching for changes every $($cfg.pollSeconds)s. Press Ctrl+C to stop."
while ($true) {
  $sig = Get-Signature
  if ($sig -ne $lastSig) {
    try {
      Invoke-Pass
      $lastSig = Get-Signature # include our own writes
      $lastError = ''
    }
    catch {
      $msg = $_.Exception.Message
      if ($msg -ne $lastError) { & $warnFn "Sync failed (will retry): $msg" }
      $lastError = $msg
      $lastSig = $sig
    }
  }
  Start-Sleep -Milliseconds ([int]($cfg.pollSeconds * 1000))
}
#endregion
