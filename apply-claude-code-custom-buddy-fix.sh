#!/bin/bash
#
# Claude Code Custom Buddy Fix Script (Unified)
#
# Patches 6 functions via AST for full buddy customization + unlock:
#
#   A. Unlock (remove access restrictions):
#     1. isBuddyLive()   — remove firstParty + essentialTraffic checks
#     2. buddyReactAPI()  — remove firstParty + essentialTraffic checks
#
#   B. Customize (support config overrides):
#     3. getCompanion()      — read companionOverride for bones
#     4. renderSprite()      — customSprite fallback
#     5. spriteFrameCount()  — customSprite length
#     6. renderFace()        — customFace fallback
#
#   C. Control switches (exported to globalThis):
#     globalThis.__buddyConfig = {
#       unlocked: true,      // buddy availability bypass active
#       customized: true,    // companion override active
#       version: "2.0"       // patch version
#     }
#
# Usage:
#   ./apply-claude-code-custom-buddy-fix.sh                    # Apply
#   ./apply-claude-code-custom-buddy-fix.sh /path/to/cli.js    # Specific file
#   ./apply-claude-code-custom-buddy-fix.sh --check            # Check only
#   ./apply-claude-code-custom-buddy-fix.sh --restore          # Restore
#
# Config example (~/.claude.json):
#   "companion": { "name": "Nimbus", "personality": "...", "hatchedAt": ... },
#   "companionOverride": {
#     "species": "dragon", "rarity": "legendary", "eye": "✦",
#     "hat": "wizard", "shiny": true,
#     "stats": { "DEBUGGING": 100, "WISDOM": 100 },
#     "customFace": "({E}ω{E})",
#     "customSprite": [
#       ["            ","  /^\\  /^\\  "," <  {E}  {E}  > "," (   ~~   ) ","  \`-vvvv-´  "],
#       ["            ","  /^\\  /^\\  "," <  {E}  {E}  > "," (        ) ","  \`-vvvv-´  "],
#       ["   ~    ~   ","  /^\\  /^\\  "," <  {E}  {E}  > "," (   ~~   ) ","  \`-vvvv-´  "]
#     ]
#   }
#

set -e

BACKUP_SUFFIX="backup-custom-buddy"
FIX_DESCRIPTION="Unified buddy unlock + customization (AST-based, 6 patch points)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[X]${NC} $1"; }
info()    { echo -e "${BLUE}[>]${NC} $1"; }

CHECK_ONLY=false; RESTORE=false; CLI_PATH_ARG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --check|-c) CHECK_ONLY=true; shift ;;
        --restore|-r) RESTORE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [options] [cli.js path]"
            echo ""; echo "$FIX_DESCRIPTION"
            echo ""; echo "Options:"
            echo "  --check, -c    Check only"; echo "  --restore, -r  Restore backup"
            exit 0 ;;
        -*) error "Unknown option: $1"; exit 1 ;;
        *) [[ -z "$CLI_PATH_ARG" ]] && CLI_PATH_ARG="$1" || { error "Unexpected: $1"; exit 1; }; shift ;;
    esac
done

find_cli_path() {
    local locations=(
        "$HOME/.claude/local/node_modules/@anthropic-ai/claude-code/cli.js"
        "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"
        "/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js"
    )
    command -v npm &>/dev/null && {
        local r; r=$(npm root -g 2>/dev/null || true)
        [[ -n "$r" ]] && locations+=("$r/@anthropic-ai/claude-code/cli.js")
    }
    for p in "${locations[@]}"; do [[ -f "$p" ]] && echo "$p" && return 0; done
    return 1
}

if [[ -n "$CLI_PATH_ARG" ]]; then
    [[ -f "$CLI_PATH_ARG" ]] && CLI_PATH="$CLI_PATH_ARG" && info "Using: $CLI_PATH" \
        || { error "Not found: $CLI_PATH_ARG"; exit 1; }
else
    CLI_PATH=$(find_cli_path) || { error "cli.js not found"; exit 1; }
    info "Found Claude Code: $CLI_PATH"
fi
CLI_DIR=$(dirname "$CLI_PATH")

if $RESTORE; then
    B=$(ls -t "$CLI_DIR"/cli.js.${BACKUP_SUFFIX}-* 2>/dev/null | head -1)
    [[ -n "$B" ]] && cp "$B" "$CLI_PATH" && success "Restored: $B" && exit 0
    error "No backup found"; exit 1
fi

echo ""

ACORN_PATH="/tmp/acorn-claude-fix.js"
[[ ! -f "$ACORN_PATH" ]] && info "Downloading acorn..." && \
    curl -sL "https://unpkg.com/acorn@8.14.0/dist/acorn.js" -o "$ACORN_PATH"

PATCH_SCRIPT=$(mktemp)
cat > "$PATCH_SCRIPT" << 'PATCH_EOF'
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

// ════════════════════════════════════════════════════════════
// Phase 1: Locate isEssentialTraffic function name
// Pattern: function XX(){ return YY() === "essential-traffic" }
// ════════════════════════════════════════════════════════════

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
if (etFnName) console.log('FOUND:isEssentialTraffic → ' + etFnName + '()');
else console.log('WARN:isEssentialTraffic not found — nonessential bypass skipped');

// ════════════════════════════════════════════════════════════
// Phase 2: Locate all 6 target functions
// ════════════════════════════════════════════════════════════

const T = {};  // targets
const V = {};  // extracted vars

walk(ast, n => {
    if (n.type !== 'FunctionDeclaration' || !n.id) return;
    const s = src(n);
    const name = n.id.name;
    const body = n.body;

    // ── 1. isBuddyLive ──
    // 0 params, has "firstParty" + etFnName + Date/getMonth
    if (!T.buddyLive && n.params.length === 0 && etFnName &&
        s.includes('"firstParty"') && s.includes('getMonth') && s.includes(etFnName + '()')) {
        // Find the two IfStatements to remove: firstParty check + essentialTraffic check
        const stmtsToRemove = [];
        for (const stmt of body.body) {
            if (stmt.type !== 'IfStatement') continue;
            const test = stmt.test;
            // if(authType !== "firstParty") return false
            if (test.type === 'BinaryExpression' && test.operator === '!==' &&
                ((test.right.type === 'Literal' && test.right.value === 'firstParty') ||
                 (test.left.type === 'Literal' && test.left.value === 'firstParty'))) {
                stmtsToRemove.push({ stmt, type: 'firstParty' });
            }
            // if(essentialTraffic()) return false
            if (test.type === 'CallExpression' && test.callee.type === 'Identifier' &&
                test.callee.name === etFnName) {
                stmtsToRemove.push({ stmt, type: 'essentialTraffic' });
            }
        }
        T.buddyLive = n;
        V.buddyLive = { fnName: name, stmtsToRemove };
        console.log('FOUND:isBuddyLive ' + name + '() — ' + stmtsToRemove.length + ' checks to remove');
    }

    // ── 2. buddyReactAPI ──
    // async, contains "buddy_react" string
    if (!T.buddyReact && n.async && s.includes('buddy_react')) {
        const stmtsToRemove = [];
        for (const stmt of body.body) {
            if (stmt.type !== 'IfStatement') continue;
            const test = stmt.test;
            // if(authType !== "firstParty") return null
            if (test.type === 'BinaryExpression' && test.operator === '!==' &&
                ((test.right.type === 'Literal' && test.right.value === 'firstParty') ||
                 (test.left.type === 'Literal' && test.left.value === 'firstParty'))) {
                stmtsToRemove.push({ stmt, type: 'firstParty' });
            }
            // if(essentialTraffic()) return null
            if (etFnName && test.type === 'CallExpression' && test.callee.type === 'Identifier' &&
                test.callee.name === etFnName) {
                stmtsToRemove.push({ stmt, type: 'essentialTraffic' });
            }
        }
        T.buddyReact = n;
        V.buddyReact = { fnName: name, stmtsToRemove };
        console.log('FOUND:buddyReactAPI ' + name + '() — ' + stmtsToRemove.length + ' checks to remove');
    }

    // ── 3. getCompanion ──
    // 0 params, .companion access, {bones:} destructure, spread return
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
        console.log('FOUND:getCompanion ' + name + '() — config=' + V.getCompanion.configCall);
    }

    // ── 4. renderSprite ──
    // 2 params, 2nd default=0, replaceAll("{E}"), .species
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
        console.log('FOUND:renderSprite ' + name + '() — BODIES=' + V.renderSprite.bodiesVar);
    }

    // ── 5. spriteFrameCount ──
    // 1 param, single return BODIES[x].length, short
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

    // ── 6. renderFace ──
    // 1 param, let eye=.eye, switch(.species)
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

// ════════════════════════════════════════════════════════════
// Phase 3: Verify
// ════════════════════════════════════════════════════════════

const found = Object.keys(T);
const missing = ['buddyLive','buddyReact','getCompanion','renderSprite','spriteFrameCount','renderFace']
    .filter(k => !T[k]);

if (found.length === 0) { console.error('NOT_FOUND:No targets matched'); process.exit(1); }
for (const m of missing) console.log('WARN:' + m + '() not found');

if (!T.getCompanion) {
    console.error('NOT_FOUND:getCompanion is required — cannot determine config accessor');
    process.exit(1);
}

if (checkOnly) {
    console.log('NEEDS_PATCH');
    console.log('PATCH_COUNT:' + found.length);
    process.exit(1);
}

// ════════════════════════════════════════════════════════════
// Phase 4: Build replacements
// ════════════════════════════════════════════════════════════

const cfgCall = V.getCompanion.configCall;
let replacements = [];

// ── A1: isBuddyLive — remove firstParty + essentialTraffic if-stmts ──
if (T.buddyLive) {
    for (const { stmt, type } of V.buddyLive.stmtsToRemove) {
        replacements.push({
            start: stmt.start, end: stmt.end,
            replacement: `/*${MARKER}:${type}_bypass*/`,
            name: 'buddyLive.' + type
        });
    }
    console.log('PATCH:isBuddyLive — removed ' + V.buddyLive.stmtsToRemove.length + ' access checks');
}

// ── A2: buddyReactAPI — remove ONLY essentialTraffic, keep firstParty ──
// firstParty check guards against pointless 403s when no OAuth credentials
// exist (API Key users). essentialTraffic is the only one to decouple.
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
        // firstParty check is intentionally kept — no OAuth = no API call
    }
    if (removed > 0) console.log('PATCH:buddyReactAPI — removed essentialTraffic check (firstParty kept)');
    else console.log('WARN:buddyReactAPI — no essentialTraffic check found to remove');
}

// ── B3: getCompanion — inject companionOverride merge ──
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
    console.log('PATCH:getCompanion — injected companionOverride merge');
}

// ── B4: renderSprite — customSprite fallback ──
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
    console.log('PATCH:renderSprite — customSprite fallback');
}

// ── B5: spriteFrameCount — customSprite length ──
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
    console.log('PATCH:spriteFrameCount — customSprite length');
}

// ── B6: renderFace — customFace fallback ──
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
    console.log('PATCH:renderFace — customFace fallback');
}

// ── C: Control switches — inject at end of file ──
const controlSwitch =
    `\n;globalThis.__buddyConfig={unlocked:${!!T.buddyLive},customized:${!!T.getCompanion},` +
    `version:"2.0",patches:${JSON.stringify(replacements.map(r=>r.name))}};/*${MARKER}:ctrl*/\n`;
replacements.push({
    start: code.length, end: code.length,
    replacement: controlSwitch, name: 'controlSwitch'
});
console.log('PATCH:controlSwitch — exported globalThis.__buddyConfig');

// ════════════════════════════════════════════════════════════
// Phase 5: Apply (end-to-start)
// ════════════════════════════════════════════════════════════

replacements.sort((a, b) => b.start - a.start);
let newCode = code;
for (const r of replacements) {
    newCode = newCode.slice(0, r.start) + r.replacement + newCode.slice(r.end);
}

if (newCode === code) { console.error('VERIFY_FAILED:No changes'); process.exit(1); }
if (!newCode.includes(MARKER)) { console.error('VERIFY_FAILED:Marker missing'); process.exit(1); }

// Syntax verification
try { acorn.parse(newCode, { ecmaVersion: 2022, sourceType: 'module' }); }
catch (e) {
    console.error('VERIFY_FAILED:Syntax error after patching: ' + e.message);
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
PATCH_EOF

CHECK_ARG=""; $CHECK_ONLY && CHECK_ARG="--check"
export BACKUP_SUFFIX
OUTPUT=$(node "$PATCH_SCRIPT" "$ACORN_PATH" "$CLI_PATH" "$CHECK_ARG" 2>&1) || true
EXIT_CODE=$?
rm -f "$PATCH_SCRIPT"

while IFS= read -r line; do
    case "$line" in
        ALREADY_PATCHED)   success "Already patched (v2 marker found)"; exit 0 ;;
        PARSE_ERROR:*)     error "Parse: ${line#PARSE_ERROR:}"; exit 1 ;;
        NOT_FOUND:*)       error "${line#NOT_FOUND:}"; exit 1 ;;
        FOUND:*)           info "Found: ${line#FOUND:}" ;;
        PATCH:*)           info "Patch: ${line#PATCH:}" ;;
        WARN:*)            warning "${line#WARN:}" ;;
        VERIFY:*)          info "${line#VERIFY:}" ;;
        CONTEXT:*)         echo "  ${line#CONTEXT:}" ;;
        NEEDS_PATCH)       echo ""; warning "Patch needed — run without --check" ;;
        PATCH_COUNT:*)     info "Can patch ${line#PATCH_COUNT:} target(s)"; exit 1 ;;
        BACKUP:*)          echo ""; echo "  Backup: ${line#BACKUP:}" ;;
        VERIFY_FAILED:*)   error "${line#VERIFY_FAILED:}"; exit 1 ;;
        SUCCESS:*)
            echo ""
            success "Applied ${line#SUCCESS:} patches"
            echo ""
            info "A. Unlock:    isBuddyLive — firstParty/essentialTraffic bypassed"
            info "              buddyReactAPI — essentialTraffic bypassed (firstParty kept)"
            info "B. Customize: getCompanion + renderSprite + spriteFrameCount + renderFace"
            info "C. Control:   globalThis.__buddyConfig = { unlocked, customized, version, patches }"
            echo ""
            info "Add to ~/.claude.json (full example):"
            echo ""
            cat << 'EXAMPLE'
  "companion": {
    "name": "Nimbus",
    "personality": "A brooding philosopher who quotes Nietzsche at your semicolons",
    "hatchedAt": 1743465600000
  },
  "companionOverride": {
    "species": "dragon",
    "rarity": "legendary",
    "eye": "✦",
    "hat": "wizard",
    "shiny": true,
    "stats": {
      "DEBUGGING": 100,
      "PATIENCE": 100,
      "CHAOS": 0,
      "WISDOM": 100,
      "SNARK": 0
    },
    "customFace": "({E}ω{E})",
    "customSprite": [
      ["            ", "  /^\\  /^\\  ", " <  {E}  {E}  > ", " (   ~~   ) ", "  `-vvvv-´  "],
      ["            ", "  /^\\  /^\\  ", " <  {E}  {E}  > ", " (        ) ", "  `-vvvv-´  "],
      ["   ~    ~   ", "  /^\\  /^\\  ", " <  {E}  {E}  > ", " (   ~~   ) ", "  `-vvvv-´  "]
    ]
  }

  Valid species:  duck goose blob cat dragon octopus owl penguin
                  turtle snail ghost axolotl capybara cactus robot
                  rabbit mushroom chonk (or any name with customSprite)
  Valid rarity:   common uncommon rare epic legendary
  Valid eye:      · ✦ × ◉ @ ° (or any single char)
  Valid hat:      none crown tophat propeller halo wizard beanie tinyduck
  Sprite rules:   1-3 frames, each 5 lines × ~12 chars, {E} = eye placeholder
EXAMPLE
            echo ""
            warning "Restart Claude Code for changes to take effect"
            ;;
    esac
done <<< "$OUTPUT"
exit $EXIT_CODE
