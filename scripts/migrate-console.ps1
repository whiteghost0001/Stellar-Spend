param(
    [string]$TargetDir = "src"
)

$ErrorActionPreference = "Continue"

function Add-LoggerImport {
    param([string]$Content)
    if ($Content -match "from\s+['""]@/lib/logger['""]") { return $Content }
    if ($Content -match "import\s+\{.*logger.*\}") { return $Content }
    # Prepend import to content
    $Content = "import { logger } from '@/lib/logger';`n" + $Content
    return $Content
}

function Replace-ConsoleCalls {
    param([string]$Content)
    $Content = $Content -replace '\bconsole\.error\(', 'logger.error('
    $Content = $Content -replace '\bconsole\.warn\(',   'logger.warn('
    $Content = $Content -replace '\bconsole\.log\(',    'logger.info('
    $Content = $Content -replace '\bconsole\.debug\(',  'logger.debug('
    return $Content
}

function Fix-ErrorArgs {
    param([string]$Content)

    # logger.error('msg', X) -> logger.error('msg', {}, X) when X is not {object}
    # Pattern: logger.error(string_literal, non_object_expression) -> add {} in between
    $re1 = "(logger\.error\([`"'][^`"']*[`"'],\s*)((?!\{)[a-zA-Z_][\w\.]*(?:\([^)]*\))?)\s*\)"
    # logger.error("msg", X) same pattern
    $re2 = '(logger\.error\("[^"]*",\s*)((?!\{)[a-zA-Z_][\w\.]*(?:\([^)]*\))?)\s*\)'
    # logger.error(`msg`, X) same pattern
    $re3 = '(logger\.error\(`[^`]*`,\s*)((?!\{)[a-zA-Z_][\w\.]*(?:\([^)]*\))?)\s*\)'

    foreach ($re in @($re1, $re2, $re3)) {
        $Content = $Content -replace $re, '$1{}, $2)'
    }

    # Also handle template literal with colon: logger.error(`msg: ${x}`, err)
    $re4 = '(logger\.error\(`[^`]*`,\s*)((\w+))\s*\)'
    $Content = $Content -replace $re4, '$1{}, $2)'

    return $Content
}

function Process-File {
    param([string]$Path)
    $content = [System.IO.File]::ReadAllText($Path)
    $hasConsole = $content -match '\bconsole\.(error|warn|log|debug)\('
    if (-not $hasConsole) { return $false }

    $original = $content

    # Don't modify logger.ts itself
    if ($Path -match '\\logger\.ts$') { return $false }

    if ($Path -match 'scripts\\') { return $false }

    $content = Add-LoggerImport $content
    $content = Replace-ConsoleCalls $content
    $content = Fix-ErrorArgs $content

    if ($content -ne $original) {
        [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
        $rel = $Path.Substring((Get-Location).Path.Length + 1)
        Write-Host "  [+] $rel"
        return $true
    }
    return $false
}

Write-Host "Migrating console.* -> logger.* ..."

$files = Get-ChildItem -Path $TargetDir -Recurse -Include *.ts, *.tsx `
    | Where-Object { $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\.next\\' }

$modified = 0
foreach ($f in $files) {
    $done = Process-File $f.FullName
    if ($done) { $modified++ }
}

Write-Host "Done. Modified $modified files."
