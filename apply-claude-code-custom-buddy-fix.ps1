<#
.SYNOPSIS
    Claude Code Custom Buddy Fix Script (Unified, Windows Version)

.DESCRIPTION
    Patches 6 functions via AST for full buddy customization + unlock:

    A. Unlock (remove access restrictions):
      1. isBuddyLive()   - remove firstParty + essentialTraffic checks
      2. buddyReactAPI()  - remove essentialTraffic check (firstParty kept)

    B. Customize (support config overrides):
      3. getCompanion()      - read companionOverride for bones
      4. renderSprite()      - customSprite fallback
      5. spriteFrameCount()  - customSprite length
      6. renderFace()        - customFace fallback

    C. Control switches (exported to globalThis):
      globalThis.__buddyConfig = { unlocked, customized, version, patches }

.PARAMETER Check
    Check if fix is needed without making changes

.PARAMETER Restore
    Restore original file from backup

.PARAMETER Help
    Show help information

.PARAMETER CliPath
    Path to cli.js file (optional, auto-detect if not provided)

.EXAMPLE
    .\apply-claude-code-custom-buddy-fix.ps1

.EXAMPLE
    .\apply-claude-code-custom-buddy-fix.ps1 -Check

.EXAMPLE
    .\apply-claude-code-custom-buddy-fix.ps1 -CliPath "C:\path\to\cli.js"

.EXAMPLE
    .\apply-claude-code-custom-buddy-fix.ps1 -Restore
#>

param(
    [switch]$Check,
    [switch]$Restore,
    [switch]$Help,
    [string]$CliPath
)

# ============================================================
# Configuration
# ============================================================
$BACKUP_SUFFIX = "backup-custom-buddy"
$FIX_DESCRIPTION = "Unified buddy unlock + customization (AST-based, 6 patch points)"

# ============================================================
# Color output functions
# ============================================================
function Write-Success { param($Message) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $Message }
function Write-Warning { param($Message) Write-Host "[!] " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-FixError { param($Message) Write-Host "[X] " -ForegroundColor Red -NoNewline; Write-Host $Message }
function Write-Info { param($Message) Write-Host "[>] " -ForegroundColor Blue -NoNewline; Write-Host $Message }

# ============================================================
# Main function
# ============================================================
function Invoke-ClaudeCodeFix {
    param(
        [switch]$Check,
        [switch]$Restore,
        [switch]$Help,
        [string]$CliPath
    )

    if ($Help) {
        Write-Host @"
Claude Code $FIX_DESCRIPTION

Usage:
    .\$($MyInvocation.MyCommand.Name) [options]

Options:
    -Check      Check if fix is needed without making changes
    -Restore    Restore original file from backup
    -CliPath    Path to cli.js file (optional, auto-detect if not provided)
    -Help       Show this help message

Config example (~/.claude.json):
    "companion": { "name": "Nimbus", "personality": "...", "hatchedAt": ... },
    "companionOverride": {
        "species": "dragon", "rarity": "legendary", "eye": "stars",
        "hat": "wizard", "shiny": true,
        "stats": { "DEBUGGING": 100, "WISDOM": 100 },
        "customFace": "({E}w{E})",
        "customSprite": [ ["...", "...", "...", "...", "..."] ]
    }
"@
        return 0
    }

    # --------------------------------------------------------
    # Find Claude Code cli.js path
    # --------------------------------------------------------
    function Find-CliPath {
        $locations = @(
            (Join-Path $env:USERPROFILE ".claude\local\node_modules\@anthropic-ai\claude-code\cli.js"),
            (Join-Path $env:APPDATA "npm\node_modules\@anthropic-ai\claude-code\cli.js"),
            (Join-Path $env:ProgramFiles "nodejs\node_modules\@anthropic-ai\claude-code\cli.js"),
            (Join-Path ${env:ProgramFiles(x86)} "nodejs\node_modules\@anthropic-ai\claude-code\cli.js")
        )

        try {
            $npmRoot = & npm root -g 2>$null
            if ($npmRoot) {
                $locations += Join-Path $npmRoot "@anthropic-ai\claude-code\cli.js"
            }
        } catch {}

        foreach ($path in $locations) {
            if (Test-Path $path) {
                return $path
            }
        }
        return $null
    }

    # --------------------------------------------------------
    # Determine cliPath
    # --------------------------------------------------------
    if ($CliPath) {
        if (Test-Path $CliPath) {
            $cliPathResolved = $CliPath
            Write-Info "Using specified cli.js: $cliPathResolved"
        } else {
            Write-FixError "Specified file not found: $CliPath"
            return 1
        }
    } else {
        $cliPathResolved = Find-CliPath
        if (-not $cliPathResolved) {
            Write-FixError "Claude Code cli.js not found"
            Write-Host ""
            Write-Host "Searched locations:"
            Write-Host "  ~\.claude\local\node_modules\@anthropic-ai\claude-code\cli.js"
            Write-Host "  %APPDATA%\npm\node_modules\@anthropic-ai\claude-code\cli.js"
            Write-Host "  %ProgramFiles%\nodejs\node_modules\@anthropic-ai\claude-code\cli.js"
            Write-Host "  `$(npm root -g)\@anthropic-ai\claude-code\cli.js"
            Write-Host ""
            Write-Host "Tip: You can specify the path directly:"
            Write-Host "  .\$($MyInvocation.MyCommand.Name) -CliPath 'C:\path\to\cli.js'"
            return 1
        }
        Write-Info "Found Claude Code: $cliPathResolved"
    }

    $cliPath = $cliPathResolved

    # --------------------------------------------------------
    # Restore backup
    # --------------------------------------------------------
    if ($Restore) {
        $backups = Get-ChildItem -Path (Split-Path $cliPath) -Filter "cli.js.$BACKUP_SUFFIX-*" -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending

        if ($backups.Count -gt 0) {
            $latestBackup = $backups[0].FullName
            Copy-Item $latestBackup $cliPath -Force
            Write-Success "Restored from backup: $latestBackup"
            return 0
        } else {
            Write-FixError "No backup file found (cli.js.$BACKUP_SUFFIX-*)"
            return 1
        }
    }

    Write-Host ""

    # --------------------------------------------------------
    # Download acorn parser if needed
    # --------------------------------------------------------
    $acornPath = Join-Path $env:TEMP "acorn-claude-fix.js"
    if (-not (Test-Path $acornPath)) {
        Write-Info "Downloading acorn parser..."
        try {
            Invoke-WebRequest -Uri "https://unpkg.com/acorn@8.14.0/dist/acorn.js" -OutFile $acornPath -UseBasicParsing
        } catch {
            Write-FixError "Failed to download acorn parser"
            return 1
        }
    }

    # --------------------------------------------------------
    # Node.js patch script (identical to bash version)
    # --------------------------------------------------------
    $patchScript = @'
const fs = require('fs');
const acorn = require(process.argv[2]);
const cliPath = process.argv[3];
const checkOnly = process.argv[4] === '--check';
const backupSuffix = process.env.BACKUP_SUFFIX || 'backup';

let code = fs.readFileSync(cliPath, 'utf-8');
let shebang = '';
if (code.startsWith('#!')) {
    const idx = code.indexOf('\n');
    shebang = code.slice(0, idx + 1);
    code = code.slice(idx + 1);
}

const MARKER = '__ccbuddy_v2__';
if (code.includes(MARKER)) { console.log('ALREADY_PATCHED'); process.exit(2); }

let ast;
try { ast = acorn.parse(code, { ecmaVersion: 2022, sourceType: 'module' }); }
catch (e) { console.error('PARSE_ERROR:' + e.message); process.exit(1); }

const src = n => code.slice(n.start, n.end);
function walk(node, cb) {
    if (!node || typeof node !== 'object') return;
    cb(node);
    for (const k in node) {
        if (node[k] && typeof node[k] === 'object') {
            if (Array.isArray(node[k])) node[k].forEach(c => walk(c, cb));
            else walk(node[k], cb);
        }
    }
}

// Phase 1: Locate isEssentialTraffic function name
let etFnName = null;
walk(ast, n => {
    if (n.type !== 'FunctionDeclaration' || !n.id || n.params.length !== 0) return;
    const b = n.body.body;
    if (!b || b.length !== 1 || b[0].type !== 'ReturnStatement') return;
    const arg = b[0].argument;
    if (!arg || arg.type !== 'BinaryExpression' || arg.operator !== '===') return;
    if ((arg.right.type === 'Literal' && arg.right.value === 'essential-traffic') ||
        (arg.left.type === 'Literal' && arg.left.value === 'essential-traffic')) {
        etFnName = n.id.name;
    }
});
if (etFnName) console.log('FOUND:isEssentialTraffic -> ' + etFnName + '()');
else console.log('WARN:isEssentialTraffic not found');

// Phase 2: Locate all 6 target functions
const T = {};
const V = {};

walk(ast, n => {
    if (n.type !== 'FunctionDeclaration' || !n.id) return;
    const s = src(n);
    const name = n.id.name;
    const body = n.body;

    // 1. isBuddyLive
    if (!T.buddyLive && n.params.length === 0 && etFnName &&
        s.includes('"firstParty"') && s.includes('getMonth') && s.includes(etFnName + '()')) {
        const stmtsToRemove = [];
        for (const stmt of body.body) {
            if (stmt.type !== 'IfStatement') continue;
            const test = stmt.test;
            if (test.type === 'BinaryExpression' && test.operator === '!==' &&
                ((test.right.type === 'Literal' && test.right.value === 'firstParty') ||
                 (test.left.type === 'Literal' && test.left.value === 'firstParty'))) {
                stmtsToRemove.push({ stmt, type: 'firstParty' });
            }
            if (test.type === 'CallExpression' && test.callee.type === 'Identifier' &&
                test.callee.name === etFnName) {
                stmtsToRemove.push({ stmt, type: 'essentialTraffic' });
            }
        }
        T.buddyLive = n;
        V.buddyLive = { fnName: name, stmtsToRemove };
        console.log('FOUND:isBuddyLive ' + name + '() -- ' + stmtsToRemove.length + ' checks to remove');
    }

    // 2. buddyReactAPI
    if (!T.buddyReact && n.async && s.includes('buddy_react')) {
        const stmtsToRemove = [];
        for (const stmt of body.body) {
            if (stmt.type !== 'IfStatement') continue;
            const test = stmt.test;
            if (test.type === 'BinaryExpression' && test.operator === '!==' &&
                ((test.right.type === 'Literal' && test.right.value === 'firstParty') ||
                 (test.left.type === 'Literal' && test.left.value === 'firstParty'))) {
                stmtsToRemove.push({ stmt, type: 'firstParty' });
            }
            if (etFnName && test.type === 'CallExpression' && test.callee.type === 'Identifier' &&
                test.callee.name === etFnName) {
                stmtsToRemove.push({ stmt, type: 'essentialTraffic' });
            }
        }
        T.buddyReact = n;
        V.buddyReact = { fnName: name, stmtsToRemove };
        console.log('FOUND:buddyReactAPI ' + name + '() -- ' + stmtsToRemove.length + ' checks to remove');
    }

    // 3. getCompanion
    if (!T.getCompanion && n.params.length === 0 && body.body?.length === 4) {
        const [s1, s2, s3, s4] = body.body;
        if (s1?.type !== 'VariableDeclaration') return;
        const d1 = s1.declarations[0];
        if (!d1?.init || d1.init.type !== 'MemberExpression' || d1.init.property?.name !== 'companion') return;
        if (d1.init.object?.type !== 'CallExpression') return;
        if (s2?.type !== 'IfStatement') return;
        if (s3?.type !== 'VariableDeclaration') return;
        const d3 = s3.declarations[0];
        if (!d3?.id || d3.id.type !== 'ObjectPattern') return;
        const bp = d3.id.properties?.find(p => p.key?.name === 'bones');
        if (!bp) return;
        if (s4?.type !== 'ReturnStatement') return;
        T.getCompanion = n;
        V.getCompanion = {
            fnName: name,
            configVar: d1.id.name,
            configCall: src(d1.init.object),
            bonesVar: bp.value.name,
            rollCall: src(d3.init),
        };
        console.log('FOUND:getCompanion ' + name + '() -- config=' + V.getCompanion.configCall);
    }

    // 4. renderSprite
    if (!T.renderSprite && n.params.length === 2) {
        const p1 = n.params[1];
        if (p1?.type !== 'AssignmentPattern' || p1.right?.value !== 0) return;
        if (!s.includes('replaceAll') || !s.includes('{E}') || !s.includes('.species')) return;
        const firstStmt = body.body[0];
        if (!firstStmt || firstStmt.type !== 'VariableDeclaration' || firstStmt.declarations.length !== 2) return;
        const decl0 = firstStmt.declarations[0];
        const decl1 = firstStmt.declarations[1];
        T.renderSprite = n;
        V.renderSprite = {
            fnName: name,
            bonesParam: n.params[0].name,
            frameParam: p1.left.name,
            framesVar: decl0.id.name,
            linesVar: decl1.id.name,
            bodiesVar: src(decl0.init.object),
            stmt0Node: firstStmt,
            decl1InitSrc: src(decl1.init),
        };
        console.log('FOUND:renderSprite ' + name + '() -- BODIES=' + V.renderSprite.bodiesVar);
    }

    // 5. spriteFrameCount
    if (!T.spriteFrameCount && n.params.length === 1 && body.body?.length === 1 && (n.end - n.start) < 80) {
        const ret = body.body[0];
        if (ret?.type !== 'ReturnStatement') return;
        const arg = ret.argument;
        if (!arg || arg.type !== 'MemberExpression' || arg.property?.name !== 'length') return;
        if (arg.object?.type !== 'MemberExpression') return;
        T.spriteFrameCount = n;
        V.spriteFrameCount = {
            fnName: name,
            speciesParam: n.params[0].name,
            bodiesVar: src(arg.object.object),
        };
        console.log('FOUND:spriteFrameCount ' + name + '()');
    }

    // 6. renderFace
    if (!T.renderFace && n.params.length === 1 && body.body?.length === 2) {
        const [stmt1, stmt2] = body.body;
        if (stmt1?.type !== 'VariableDeclaration') return;
        if (stmt1.declarations[0]?.init?.property?.name !== 'eye') return;
        if (stmt2?.type !== 'SwitchStatement') return;
        if (stmt2.discriminant?.property?.name !== 'species') return;
        T.renderFace = n;
        V.renderFace = {
            fnName: name,
            bonesParam: n.params[0].name,
            eyeVar: stmt1.declarations[0].id.name,
        };
        console.log('FOUND:renderFace ' + name + '()');
    }
});

// Phase 3: Verify
const found = Object.keys(T);
const missing = ['buddyLive','buddyReact','getCompanion','renderSprite','spriteFrameCount','renderFace']
    .filter(k => !T[k]);

if (found.length === 0) { console.error('NOT_FOUND:No targets matched'); process.exit(1); }
for (const m of missing) console.log('WARN:' + m + '() not found');

if (!T.getCompanion) {
    console.error('NOT_FOUND:getCompanion is required');
    process.exit(1);
}

if (checkOnly) {
    console.log('NEEDS_PATCH');
    console.log('PATCH_COUNT:' + found.length);
    process.exit(1);
}

// Phase 4: Build replacements
const cfgCall = V.getCompanion.configCall;
let replacements = [];

// A1: isBuddyLive -- remove firstParty + essentialTraffic
if (T.buddyLive) {
    for (const { stmt, type } of V.buddyLive.stmtsToRemove) {
        replacements.push({
            start: stmt.start, end: stmt.end,
            replacement: `/*${MARKER}:${type}_bypass*/`,
            name: 'buddyLive.' + type
        });
    }
    console.log('PATCH:isBuddyLive -- removed ' + V.buddyLive.stmtsToRemove.length + ' access checks');
}

// A2: buddyReactAPI -- remove ONLY essentialTraffic, keep firstParty
if (T.buddyReact) {
    let removed = 0;
    for (const { stmt, type } of V.buddyReact.stmtsToRemove) {
        if (type === 'essentialTraffic') {
            replacements.push({
                start: stmt.start, end: stmt.end,
                replacement: `/*${MARKER}:${type}_bypass*/`,
                name: 'buddyReact.' + type
            });
            removed++;
        }
    }
    if (removed > 0) console.log('PATCH:buddyReactAPI -- removed essentialTraffic (firstParty kept)');
    else console.log('WARN:buddyReactAPI -- no essentialTraffic check found');
}

// B3: getCompanion -- companionOverride merge
if (T.getCompanion) {
    const v = V.getCompanion;
    const replacement =
        `function ${v.fnName}(){/*${MARKER}*/` +
        `let ${v.configVar}=${v.configCall}.companion;` +
        `if(!${v.configVar})return;` +
        `let{bones:${v.bonesVar}}=${v.rollCall};` +
        `var _ov=${v.configCall}.companionOverride;` +
        `if(_ov){` +
            `var _origSt=${v.bonesVar}.stats;` +
            `if(_ov.stats)_origSt=Object.assign({},_origSt,_ov.stats);` +
            `Object.assign(${v.bonesVar},_ov);` +
            `${v.bonesVar}.stats=_ov.stats?Object.assign({},${v.rollCall}.bones.stats,_ov.stats):_origSt;` +
            `delete ${v.bonesVar}.customSprite;delete ${v.bonesVar}.customFace` +
        `}` +
        `return{...${v.configVar},...${v.bonesVar}}}`;
    replacements.push({
        start: T.getCompanion.start, end: T.getCompanion.end,
        replacement, name: 'getCompanion'
    });
    console.log('PATCH:getCompanion -- injected companionOverride merge');
}

// B4: renderSprite -- customSprite fallback
if (T.renderSprite) {
    const v = V.renderSprite;
    const replacement =
        `var _csp=${cfgCall}.companionOverride;` +
        `let ${v.framesVar}=(_csp&&Array.isArray(_csp.customSprite)&&_csp.customSprite.length>0)` +
        `?_csp.customSprite:${v.bodiesVar}[${v.bonesParam}.species],` +
        `${v.linesVar}=${v.decl1InitSrc};`;
    replacements.push({
        start: v.stmt0Node.start, end: v.stmt0Node.end,
        replacement, name: 'renderSprite'
    });
    console.log('PATCH:renderSprite -- customSprite fallback');
}

// B5: spriteFrameCount -- customSprite length
if (T.spriteFrameCount) {
    const v = V.spriteFrameCount;
    const replacement =
        `function ${v.fnName}(${v.speciesParam}){` +
        `var _csp3=${cfgCall}.companionOverride;` +
        `if(_csp3&&Array.isArray(_csp3.customSprite)&&_csp3.customSprite.length>0)` +
        `return _csp3.customSprite.length;` +
        `return ${v.bodiesVar}[${v.speciesParam}].length}`;
    replacements.push({
        start: T.spriteFrameCount.start, end: T.spriteFrameCount.end,
        replacement, name: 'spriteFrameCount'
    });
    console.log('PATCH:spriteFrameCount -- customSprite length');
}

// B6: renderFace -- customFace fallback
if (T.renderFace) {
    const v = V.renderFace;
    const bodyStart = T.renderFace.body.start + 1;
    const injection =
        `var _cf4=${cfgCall}.companionOverride;` +
        `if(_cf4&&typeof _cf4.customFace==="string")` +
        `return _cf4.customFace.replaceAll("{E}",${v.bonesParam}.eye);`;
    replacements.push({
        start: bodyStart, end: bodyStart,
        replacement: injection, name: 'renderFace'
    });
    console.log('PATCH:renderFace -- customFace fallback');
}

// C: Control switches
const controlSwitch =
    `\n;globalThis.__buddyConfig={unlocked:${!!T.buddyLive},customized:${!!T.getCompanion},` +
    `version:"2.0",patches:${JSON.stringify(replacements.map(r=>r.name))}};/*${MARKER}:ctrl*/\n`;
replacements.push({
    start: code.length, end: code.length,
    replacement: controlSwitch, name: 'controlSwitch'
});
console.log('PATCH:controlSwitch -- exported globalThis.__buddyConfig');

// Phase 5: Apply (end-to-start)
replacements.sort((a, b) => b.start - a.start);
let newCode = code;
for (const r of replacements) {
    newCode = newCode.slice(0, r.start) + r.replacement + newCode.slice(r.end);
}

if (newCode === code) { console.error('VERIFY_FAILED:No changes'); process.exit(1); }
if (!newCode.includes(MARKER)) { console.error('VERIFY_FAILED:Marker missing'); process.exit(1); }

try { acorn.parse(newCode, { ecmaVersion: 2022, sourceType: 'module' }); }
catch (e) {
    console.error('VERIFY_FAILED:Syntax error: ' + e.message);
    const p = e.pos;
    if (p) console.error('CONTEXT:' + newCode.slice(Math.max(0,p-60),p) + '<<<HERE>>>' + newCode.slice(p,p+60));
    process.exit(1);
}
console.log('VERIFY:AST parse OK');

const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const backupPath = cliPath + '.' + backupSuffix + '-' + timestamp;
fs.copyFileSync(cliPath, backupPath);
console.log('BACKUP:' + backupPath);

fs.writeFileSync(cliPath, shebang + newCode);
console.log('SUCCESS:' + (replacements.length));
'@

    # --------------------------------------------------------
    # Write and execute patch script
    # --------------------------------------------------------
    $patchFile = Join-Path $env:TEMP "claude-buddy-patch-$(Get-Random).js"
    $patchScript | Out-File -FilePath $patchFile -Encoding utf8 -NoNewline

    $checkArg = if ($Check) { "--check" } else { "" }
    $env:BACKUP_SUFFIX = $BACKUP_SUFFIX

    try {
        $output = & node $patchFile $acornPath $cliPath $checkArg 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        Remove-Item $patchFile -ErrorAction SilentlyContinue
    }

    # --------------------------------------------------------
    # Process output
    # --------------------------------------------------------
    foreach ($line in $output) {
        $lineStr = "$line"
        switch -Regex ($lineStr) {
            '^ALREADY_PATCHED$' {
                Write-Success "Already patched (v2 marker found)"
                return 0
            }
            '^PARSE_ERROR:(.+)$' {
                Write-FixError "Parse: $($Matches[1])"
                return 1
            }
            '^NOT_FOUND:(.+)$' {
                Write-FixError $Matches[1]
                return 1
            }
            '^FOUND:(.+)$' {
                Write-Info "Found: $($Matches[1])"
            }
            '^PATCH:(.+)$' {
                Write-Info "Patch: $($Matches[1])"
            }
            '^WARN:(.+)$' {
                Write-Warning $Matches[1]
            }
            '^VERIFY:(.+)$' {
                Write-Info $Matches[1]
            }
            '^CONTEXT:(.+)$' {
                Write-Host "  $($Matches[1])"
            }
            '^NEEDS_PATCH$' {
                Write-Host ""
                Write-Warning "Patch needed - run without -Check to apply"
            }
            '^PATCH_COUNT:(.+)$' {
                Write-Info "Can patch $($Matches[1]) target(s)"
                return 1
            }
            '^BACKUP:(.+)$' {
                Write-Host ""
                Write-Host "  Backup: $($Matches[1])"
            }
            '^VERIFY_FAILED:(.+)$' {
                Write-FixError $Matches[1]
                return 1
            }
            '^SUCCESS:(.+)$' {
                Write-Host ""
                Write-Success "Applied $($Matches[1]) patches"
                Write-Host ""
                Write-Info "A. Unlock:    isBuddyLive -- firstParty/essentialTraffic bypassed"
                Write-Info "              buddyReactAPI -- essentialTraffic bypassed (firstParty kept)"
                Write-Info "B. Customize: getCompanion + renderSprite + spriteFrameCount + renderFace"
                Write-Info "C. Control:   globalThis.__buddyConfig = { unlocked, customized, version, patches }"
                Write-Host ""
                Write-Info "Add to ~/.claude.json (full example):"
                Write-Host ""
                Write-Host @'
  "companion": {
    "name": "Nimbus",
    "personality": "A brooding philosopher who quotes Nietzsche at your semicolons",
    "hatchedAt": 1743465600000
  },
  "companionOverride": {
    "species": "dragon",
    "rarity": "legendary",
    "eye": "stars",
    "hat": "wizard",
    "shiny": true,
    "stats": {
      "DEBUGGING": 100,
      "PATIENCE": 100,
      "CHAOS": 0,
      "WISDOM": 100,
      "SNARK": 0
    },
    "customFace": "({E}w{E})",
    "customSprite": [
      ["            ", "  /^\  /^\  ", " <  {E}  {E}  > ", " (   ~~   ) ", "  `-vvvv-'  "],
      ["            ", "  /^\  /^\  ", " <  {E}  {E}  > ", " (        ) ", "  `-vvvv-'  "],
      ["   ~    ~   ", "  /^\  /^\  ", " <  {E}  {E}  > ", " (   ~~   ) ", "  `-vvvv-'  "]
    ]
  }

  Valid species:  duck goose blob cat dragon octopus owl penguin
                  turtle snail ghost axolotl capybara cactus robot
                  rabbit mushroom chonk (or any name with customSprite)
  Valid rarity:   common uncommon rare epic legendary
  Valid eye:      any single character
  Valid hat:      none crown tophat propeller halo wizard beanie tinyduck
  Sprite rules:   1-3 frames, each 5 lines x ~12 chars, {E} = eye placeholder
'@
                Write-Host ""
                Write-Warning "Restart Claude Code for changes to take effect"
            }
        }
    }

    return $exitCode
}

# ============================================================
# Entry point
# ============================================================
$result = Invoke-ClaudeCodeFix -Check:$Check -Restore:$Restore -Help:$Help -CliPath $CliPath
exit $result
