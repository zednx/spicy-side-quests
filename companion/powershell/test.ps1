# Tests for the PowerShell companion. Mirrors ../test/sync.test.ts.
# Run: powershell -ExecutionPolicy Bypass -File test.ps1   (or: pwsh test.ps1)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SpicySideQuests.ps1') -Library
Write-Host "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

$script:pass = 0; $script:fail = 0
function Test($name, [scriptblock]$body) {
  try { & $body; $script:pass++; Write-Host "ok   $name" }
  catch { $script:fail++; Write-Host "FAIL $name`n     $($_.Exception.Message)`n     $($_.ScriptStackTrace -split "`n" | Select-Object -First 2)" -ForegroundColor Red }
}
function Assert-Eq($actual, $expected, $msg = '') {
  $a = if ($actual -is [array]) { $actual -join '|' } else { $actual }
  $e = if ($expected -is [array]) { $expected -join '|' } else { $expected }
  if (-not ($a -ceq $e)) { throw "$msg expected <$e> but got <$a>" }
}
function Assert-True($cond, $msg = 'expected true') { if (-not $cond) { throw $msg } }

function New-Item2([hashtable]$over) {
  $i = @{ id = 'a'; text = 'x'; tags = @(); category = 'General'; done = $false; deleted = $null; zone = $null; mapID = $null; x = $null; y = $null; created = 100; updated = 100 }
  foreach ($k in $over.Keys) { $i[$k] = $over[$k] }
  $i
}
function New-Md([hashtable]$over) {
  $i = @{ id = 'a'; text = 'x'; tags = @(); category = 'General'; done = $false; zone = $null; x = $null; y = $null }
  foreach ($k in $over.Keys) { $i[$k] = $over[$k] }
  $i
}
function Map([hashtable]$h) { $m = New-Map; foreach ($k in $h.Keys) { $m[$k] = $h[$k] }; , $m }
$NL = "`n"

# --- Lua --------------------------------------------------------------------
Test 'parses a WoW SavedVariables file' {
  $src = @'

SpicySideQuestsDB = {
["items"] = {
["abc123"] = {
["text"] = "Farm \"Arcanite\"\nnow",
["done"] = true,
["x"] = 52.1,
["tags"] = {
"farming", -- [1]
},
},
},
["order"] = {
"abc123", -- [1]
"def456", -- [2]
},
["settings"] = { ["collapsed"] = {}, },
}
Other = nil
'@
  $v = Read-LuaAssignments $src
  $item = $v['SpicySideQuestsDB']['items']['abc123']
  Assert-Eq $item['text'] "Farm `"Arcanite`"${NL}now"
  Assert-Eq $item['done'] $true
  Assert-Eq $item['x'] 52.1
  Assert-True ($item['tags'] -is [array]) 'single tag stays an array'
  Assert-Eq $item['tags'] @('farming')
  Assert-Eq $v['SpicySideQuestsDB']['order'] @('abc123', 'def456')
  Assert-True ($null -eq $v['Other'])
}

Test 'Lua round trip' {
  $data = [ordered]@{ a = 'q"uo\te|'; list = @(1, 2.5, $true); nested = [ordered]@{ 'odd key' = ([string][char]0xFC) } }
  $back = (Read-LuaAssignments "X = $(ConvertTo-Lua $data)")['X']
  Assert-Eq $back['a'] 'q"uo\te|'
  Assert-Eq $back['list'] @(1, 2.5, $true)
  Assert-Eq $back['nested']['odd key'] ([string][char]0xFC)
}

Test 'numbers use invariant culture' {
  $old = [Threading.Thread]::CurrentThread.CurrentCulture
  try {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    Assert-Eq (ConvertTo-Lua 52.1) '52.1'
    Assert-Eq (Format-TodoLine (New-Item2 @{ x = 52.14; y = 41.35 })) '- [ ] x [xy:: 52.1, 41.4] ^a'
  }
  finally { [Threading.Thread]::CurrentThread.CurrentCulture = $old }
}

# --- Markdown ---------------------------------------------------------------
$SAMPLE = (@(
    '---', 'tags: [wow]', '---', '', '# WoW Todo', '', 'Some notes stay put.', '',
    '- [ ] Loose item ^loose1', '',
    '## Professions',
    '- [ ] Farm Arcanite #farming [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3',
    '- [x] Learn Alchemy',
    '  - [ ] indented sub-task is ignored', '',
    '```', '- [ ] in a code block is ignored', '```', '',
    '## Dungeons',
    '- [-] Cancelled counts as done ^d1', ''
  ) -join $NL)

Test 'parses categories, tags, zones and ids' {
  $items = Get-MdItems (Read-Markdown $SAMPLE)
  Assert-Eq $items.Count 4
  Assert-Eq $items[0].id 'loose1'; Assert-Eq $items[0].category 'General'; Assert-Eq $items[0].text 'Loose item'
  Assert-Eq $items[1].category 'Professions'; Assert-Eq $items[1].tags @('farming'); Assert-Eq $items[1].zone 'Winterspring'; Assert-Eq $items[1].x 63.2
  Assert-True ($null -eq $items[2].id); Assert-Eq $items[2].done $true
  Assert-Eq $items[3].done $true
}

Test 'render keeps unchanged lines and non-todo content byte for byte' {
  $doc = Read-Markdown $SAMPLE
  $md = Get-MdItems $doc
  $res = Merge-Todos -Base (New-Map) -Md $md -MdTime 500 -Game (New-Map) -GameOrder @() -TombstoneDays 1e9
  $out = Format-Markdown $doc $res.items
  Assert-Eq $out ($SAMPLE.Replace('- [x] Learn Alchemy', "- [x] Learn Alchemy ^$($md[2].id)"))
  $base = New-Map; foreach ($i in $res.items) { $base[$i.id] = $i }
  $doc2 = Read-Markdown $out
  $res2 = Merge-Todos -Base $base -Md (Get-MdItems $doc2) -MdTime 600 -Game (New-Map) -GameOrder @() -TombstoneDays 1e9
  Assert-Eq (Format-Markdown $doc2 $res2.items) $out
  Assert-Eq $res2.log.Count 0
}

Test 'render adds new items to their section and creates new sections' {
  $doc = Read-Markdown "# T${NL}${NL}## Professions${NL}- [ ] One ^p1${NL}${NL}Notes${NL}"
  $items = @(
    (New-Item2 @{ id = 'p1'; text = 'One'; category = 'Professions' }),
    (New-Item2 @{ id = 'p2'; text = 'Two'; category = 'professions'; tags = @('herb') }),
    (New-Item2 @{ id = 'r1'; text = 'Raid'; category = 'Raids'; done = $true; zone = 'Molten Core' })
  )
  Assert-Eq (Format-Markdown $doc $items) ("# T${NL}${NL}## Professions${NL}- [ ] One ^p1${NL}- [ ] Two #herb ^p2${NL}${NL}Notes${NL}${NL}## Raids${NL}- [x] Raid [zone:: Molten Core] ^r1${NL}")
}

Test 'CRLF files stay CRLF' {
  $doc = Read-Markdown "## A`r`n- [ ] One ^a1`r`n"
  Assert-Eq (Format-Markdown $doc @((New-Item2 @{ id = 'a1'; text = 'One'; category = 'A'; done = $true }))) "## A`r`n- [x] One ^a1`r`n"
}

# --- Merge ------------------------------------------------------------------
Test 'game completion flows to markdown' {
  $res = Merge-Todos -Base (Map @{ a = (New-Item2 @{}) }) -Md @((New-Md @{})) -MdTime 100 -Game (Map @{ a = (New-Item2 @{ done = $true; updated = 200 }) }) -GameOrder @() -TombstoneDays 1e9
  Assert-Eq $res.items[0].done $true
  Assert-True ($res.log[0] -like 'game -> markdown: completed*') $res.log[0]
}

Test 'markdown edit flows to game with a newer timestamp' {
  $res = Merge-Todos -Base (Map @{ a = (New-Item2 @{}) }) -Md @((New-Md @{ text = 'y' })) -MdTime 300 -Game (Map @{ a = (New-Item2 @{}) }) -GameOrder @() -TombstoneDays 1e9
  Assert-Eq $res.items[0].text 'y'
  Assert-Eq $res.items[0].updated 300
}

Test 'conflict: newest change wins' {
  $base = Map @{ a = (New-Item2 @{}) }
  $game = Map @{ a = (New-Item2 @{ done = $true; updated = 400 }) }
  Assert-Eq (Merge-Todos -Base $base -Md @((New-Md @{ text = 'md' })) -MdTime 300 -Game $game -GameOrder @() -TombstoneDays 1e9).items[0].done $true
  Assert-Eq (Merge-Todos -Base $base -Md @((New-Md @{ text = 'md' })) -MdTime 500 -Game $game -GameOrder @() -TombstoneDays 1e9).items[0].text 'md'
}

Test 'deleting a line in markdown deletes in game, and vice versa' {
  $base = Map @{ a = (New-Item2 @{}); b = (New-Item2 @{ id = 'b' }) }
  $game = Map @{ a = (New-Item2 @{}); b = (New-Item2 @{ id = 'b'; deleted = $true; updated = 200 }) }
  $res = Merge-Todos -Base $base -Md @((New-Md @{ id = 'b' })) -MdTime 300 -Game $game -GameOrder @() -TombstoneDays 1e9
  foreach ($i in $res.items) { Assert-Eq $i.deleted $true "item $($i.id)" }
  Assert-Eq $res.items.Count 2
}

Test 'first sync with identical items on both sides changes nothing' {
  $res = Merge-Todos -Base (New-Map) -Md @((New-Md @{})) -MdTime 999 -Game (Map @{ a = (New-Item2 @{}) }) -GameOrder @()
  Assert-Eq $res.items[0].updated 100
}

# --- End to end -------------------------------------------------------------
Test 'full sync against a fake WoW folder' {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ("wts-" + [guid]::NewGuid())
  $wow = Join-Paths $dir '_forever_'
  $addon = Join-Paths $wow 'Interface' 'AddOns' 'SpicySideQuests'
  $svDir = Join-Paths $wow 'WTF' 'Account' 'ME' 'SavedVariables'
  [void](New-Item -ItemType Directory -Force $addon); [void](New-Item -ItemType Directory -Force $svDir)
  [IO.File]::WriteAllText((Join-Paths $addon 'SpicySideQuests.toc'), '')
  $t = Get-Now
  [IO.File]::WriteAllText((Join-Paths $svDir 'SpicySideQuests.lua'), "SpicySideQuestsDB = { [`"items`"] = { [`"g1`"] = { [`"id`"] = `"g1`", [`"text`"] = `"From game`", [`"category`"] = `"Quests`", [`"tags`"] = { `"q`" }, [`"done`"] = false, [`"created`"] = $t, [`"updated`"] = $t } }, [`"order`"] = { `"g1`" }, [`"categories`"] = { `"General`", `"Quests`" } }")
  $todo = Join-Paths $dir 'vault' 'Todo.md'
  $cfg = @{ todoFile = $todo; wowPath = $wow; account = 'auto'; pollSeconds = 2 }
  $logs = New-Object 'System.Collections.Generic.List[string]'
  $log = { param($m) $logs.Add($m) }
  $warn = { param($m) $logs.Add("WARN $m") }

  $state = Invoke-SyncOnce $cfg (Read-State (Join-Path $dir 'none.json')) -Log $log -Warn $warn
  Assert-True ($null -ne $state) 'first sync'
  $written = [IO.File]::ReadAllText($todo)
  Assert-True ($written.Contains("## Quests${NL}- [ ] From game #q ^g1")) $written

  [IO.File]::WriteAllText($todo, $written.Replace('## Quests', "## Quests${NL}- [ ] Added in Obsidian #md"))
  $state = Invoke-SyncOnce $cfg $state -Log $log -Warn $warn
  $inbox = (Read-LuaAssignments ([IO.File]::ReadAllText((Join-Paths $addon 'Inbox.lua'))))['SpicySideQuests_Inbox']
  $texts = @($inbox['items'] | ForEach-Object { $_['text'] }) | Sort-Object
  Assert-Eq $texts @('Added in Obsidian', 'From game')
  Assert-True ([IO.File]::ReadAllText($todo) -match 'Added in Obsidian #md \^\w+') 'id added'

  # state file round trip, then a no-op pass
  $stateFile = Join-Path $dir 'state.json'
  Save-State $stateFile $state
  $state2 = Read-State $stateFile
  $before = [IO.File]::ReadAllText($todo)
  $logs.Clear()
  $state2 = Invoke-SyncOnce $cfg $state2 -Log $log -Warn $warn
  Assert-Eq ([IO.File]::ReadAllText($todo)) $before 'no-op pass'
  Assert-Eq $logs.Count 0 "no-op logs: $($logs -join '; ')"

  [IO.File]::WriteAllText($todo, "# nothing${NL}")
  Assert-True ($null -eq (Invoke-SyncOnce $cfg $state2 -Log $log -Warn $warn)) 'refuses mass delete'
  Assert-True (@($logs | Where-Object { $_ -like 'WARN*' }).Count -gt 0)
  Remove-Item -Recurse -Force $dir
}

# --- Security regressions ---------------------------------------------------
Test 'security: ids that look like built-in members are ordinary ids' {
  $md = Get-MdItems (Read-Markdown "- [ ] hello ^constructor${NL}- [ ] two ^ToString${NL}")
  $res = Merge-Todos -Base (New-Map) -Md $md -MdTime 1 -Game (New-Map) -GameOrder @() -TombstoneDays 1e9
  Assert-Eq (@($res.items | ForEach-Object { $_.id })) @('constructor', 'ToString')
}

Test 'security: deeply nested Lua is rejected cleanly' {
  $threw = $false
  try { [void](Read-LuaAssignments ('X = ' + ('{' * 500) + ('}' * 500))) } catch { $threw = $_.Exception.Message -like '*nested too deeply*' }
  Assert-True $threw 'expected a "nested too deeply" error'
}

Test 'security: game data cannot inject lines into the markdown file' {
  $items = @(
    (New-Item2 @{ id = 'g1'; text = "evil${NL}- [x] injected ^zzz${NL}---"; tags = @("t${NL}x", 'ok'); category = 'A'; zone = "Z]${NL}## Pwned" }),
    (New-Item2 @{ id = 'g2'; text = 'two'; category = "B${NL}## Pwned" })
  )
  Assert-Eq (Format-Markdown (Read-Markdown "## A${NL}") $items) "## A${NL}- [ ] evil - [x] injected ^zzz --- #tx #ok [zone:: Z ## Pwned] ^g1${NL}${NL}## B ## Pwned${NL}- [ ] two ^g2${NL}"
}

Test "security: pathological lines don't freeze the parser" {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  [void](Read-Markdown (@(('## a' + (' ' * 200000) + 'x'), ('- [ ] [zone::' + (' ' * 200000)), ('- [ ] x' + (' ' * 990) + 'y')) -join $NL))
  Assert-True ($sw.ElapsedMilliseconds -lt 5000) "took $($sw.ElapsedMilliseconds)ms"
}

Test 'security: terminal escape sequences are stripped from log output' {
  $e = [string][char]27; $bel = [string][char]7; $csi = [string][char]0x9b
  Assert-Eq (Get-TerminalSafe "ok $e]52;c;ZXZpbA==$bel $e[2J ${csi}31m done") 'ok ?]52;c;ZXZpbA==? ?[2J ?31m done'
}

Test 'security: hostile text is escaped in Inbox.lua' {
  $nasty = "a`"b\c]]d${NL}--e`r" + [char]0 + [char]27 + "[31m'g end`" os.exit(1) --"
  $lit = ConvertTo-Lua $nasty
  Assert-True (-not $lit.Contains("`n")) 'no raw newline'
  Assert-Eq (Read-LuaAssignments "X = $lit")['X'] $nasty 'parser round trip'
  Assert-Eq (ConvertTo-Lua ([double]::PositiveInfinity)) '0'
  Assert-Eq (ConvertTo-Lua ([double]::NaN)) '0'
  # (the Node test suite also round-trips this through a real Lua interpreter)
}

Test 'security: Read-GameData skips invalid ids and normalises text' {
  $f = Join-Path ([IO.Path]::GetTempPath()) ("wts-sec-" + [guid]::NewGuid() + '.lua')
  [IO.File]::WriteAllText($f, 'SpicySideQuestsDB = { items = { a = { id = "../../x", text = "bad" }, b = { id = "ok1", text = "line1\nline2", category = "C\n## D" } } }')
  $g = (Read-GameData $f).items
  Assert-Eq (@($g.Keys)) @('ok1')
  Assert-Eq $g['ok1'].text 'line1 line2'
  Assert-Eq $g['ok1'].category 'C ## D'
  Remove-Item -LiteralPath $f -Force
}

Test 'security: atomic writes leave no temp files behind' {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ("wts-sec-" + [guid]::NewGuid())
  [void](New-Item -ItemType Directory -Force $dir)
  $f = Join-Path $dir 'a.md'
  Write-FileAtomic $f 'one'
  Write-FileAtomic $f 'two'
  Assert-Eq ([IO.File]::ReadAllText($f)) 'two'
  Assert-Eq (@(Get-ChildItem -LiteralPath $dir).Count) 1 'only the target file remains'
  Remove-Item -Recurse -Force $dir
}

# --- Setup --------------------------------------------------------------------
Test 'setup: interactive setup with typed answers, problems and state reset' {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ("wts-setup-" + [guid]::NewGuid())
  $wow = Join-Paths $dir '_forever_'
  [void](New-Item -ItemType Directory -Force (Join-Paths $wow 'Interface' 'AddOns' 'SpicySideQuests'))
  [IO.File]::WriteAllText((Join-Paths $wow 'Interface' 'AddOns' 'SpicySideQuests' 'SpicySideQuests.toc'), '')
  foreach ($acc in 'ACC1', 'ACC2') { [void](New-Item -ItemType Directory -Force (Join-Paths $wow 'WTF' 'Account' $acc 'SavedVariables')) }
  Assert-Eq (Get-Accounts $wow) @('ACC1', 'ACC2')

  # Replace Read-Host with scripted answers ("nope.txt" is rejected first)
  $md = Join-Path $dir 'Todo.md'
  $script:answers = [Collections.Generic.Queue[string]]::new()
  foreach ($a in 'nope.txt', $md, 'y', $wow, '2') { $script:answers.Enqueue($a) }
  function script:Read-Host { param($Prompt) if ($script:answers.Count) { $script:answers.Dequeue() } else { $null } }
  try {
    $cfgFile = Join-Paths $dir 'cfg' 'config.json'
    $cfg = Invoke-Setup $cfgFile $null *> $null
    $cfg = Read-Config $cfgFile
    Assert-Eq $cfg.todoFile $md
    Assert-Eq $cfg.wowPath $wow
    Assert-Eq $cfg.account 'ACC2'

    # Enter keeps everything; running out of input is safe once defaults exist
    $script:answers.Clear()
    foreach ($a in '', '', '') { $script:answers.Enqueue($a) }
    [void](Invoke-Setup $cfgFile $cfg *> $null)
    Assert-Eq (Read-Config $cfgFile).wowPath $wow

    # No answers and no default: cancels instead of looping forever
    $script:answers.Clear()
    $threw = $false
    try { [void](Invoke-Setup (Join-Path $dir 'other.json') $null *> $null) } catch { $threw = $_.Exception.Message -like '*cancelled*' }
    Assert-True $threw 'setup cancels at end of input'
  }
  finally { Remove-Item Function:\Read-Host -ErrorAction SilentlyContinue }

  # Stale paths are reported
  $stale = @{ todoFile = $md; wowPath = (Join-Path $dir 'moved'); account = 'auto' }
  Assert-True ((Get-ConfigProblems $stale) -join ' ' -like "*WoW folder doesn't exist*")
  Assert-True ((Get-ConfigProblems @{ todoFile = $md; wowPath = $wow; account = 'GONE' }) -join ' ' -like '*"GONE" wasn''t found*')

  # Changing the markdown file forgets the old sync history; same file keeps it
  $state = Join-Path $dir 'state.json'
  [IO.File]::WriteAllText($state, '{}')
  Assert-True (-not (Reset-StateIfFileChanged $md $md $state)) 'same file keeps state'
  Assert-True (Reset-StateIfFileChanged $md (Join-Path $dir 'Other.md') $state) 'different file resets'
  Assert-True (-not (Test-Path -LiteralPath $state))
  Remove-Item -Recurse -Force $dir
}

# --- Node <-> PowerShell compatibility (only when Node 22.18+ is available) --
$node = Get-Command node -ErrorAction SilentlyContinue
$nodeOk = $false
if ($node) { $ver = (& node -v) -replace '^v', ''; $nodeOk = ([version]$ver -ge [version]'22.18') }
if ($nodeOk) {
  Test 'Node and PowerShell versions can share config and state' {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("wts-" + [guid]::NewGuid())
    $wow = Join-Paths $dir '_forever_'
    $addon = Join-Paths $wow 'Interface' 'AddOns' 'SpicySideQuests'
    $svDir = Join-Paths $wow 'WTF' 'Account' 'ME' 'SavedVariables'
    [void](New-Item -ItemType Directory -Force $addon); [void](New-Item -ItemType Directory -Force $svDir)
    [IO.File]::WriteAllText((Join-Paths $addon 'SpicySideQuests.toc'), '')
    $t = Get-Now
    [IO.File]::WriteAllText((Join-Paths $svDir 'SpicySideQuests.lua'), "SpicySideQuestsDB = { [`"items`"] = { [`"g1`"] = { [`"id`"] = `"g1`", [`"text`"] = `"Loc item`", [`"category`"] = `"Quests`", [`"tags`"] = {}, [`"zone`"] = `"Durotar`", [`"mapID`"] = 1411, [`"x`"] = 52.1, [`"y`"] = 41.4, [`"done`"] = false, [`"created`"] = $t, [`"updated`"] = $t } } }")
    $todo = Join-Paths $dir 'Todo.md'
    [IO.File]::WriteAllText($todo, "## Quests${NL}- [ ] From markdown #a #b${NL}")
    $cfgFile = Join-Path $dir 'config.json'
    Save-Config $cfgFile @{ todoFile = $todo; wowPath = $wow; account = 'auto'; pollSeconds = 2 }
    $entry = Join-Paths $PSScriptRoot '..' 'src' 'index.ts'

    & node $entry --once --config $cfgFile | Out-Null
    Assert-Eq $LASTEXITCODE 0 'node exit'
    $afterNode = [IO.File]::ReadAllText($todo)
    $logs = New-Object 'System.Collections.Generic.List[string]'
    $cfg = Read-Config $cfgFile
    $state = Invoke-SyncOnce $cfg (Read-State (Join-Path $dir 'state.json')) -Log { param($m) $logs.Add($m) } -Warn { param($m) $logs.Add($m) }
    Assert-Eq ([IO.File]::ReadAllText($todo)) $afterNode 'PowerShell pass after Node changes nothing'
    Assert-Eq $logs.Count 0 "logs: $($logs -join '; ')"

    Save-State (Join-Path $dir 'state.json') $state
    & node $entry --once --config $cfgFile | Out-Null
    Assert-Eq ([IO.File]::ReadAllText($todo)) $afterNode 'Node pass after PowerShell changes nothing'
    Remove-Item -Recurse -Force $dir
  }
}
else { Write-Host 'skip Node <-> PowerShell compatibility (Node 22.18+ not found)' }

Write-Host "`n$($script:pass) passed, $($script:fail) failed"
if ($script:fail -gt 0) { exit 1 }
