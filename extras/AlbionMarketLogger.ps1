# Albion Market Order Logger
# Captures opAuctionGetOffers responses and writes them to CSV.
#
# Requires a patched albiondata-client.exe with debugFormatMaxString raised
# (the stock client truncates strings at 240 chars, which chops off ItemTypeId,
# QualityLevel, EnchantmentLevel, SellerName, Expires, etc.).
#
# This script does NOT filter by numeric operation ID (those shift between
# expansions). It matches on the operation NAME, so it survives ID reshuffles.

$ClientPath   = "C:\Program Files\Albion Data Client\albiondata-client.exe"
$OutputFolder = "$env:USERPROFILE\Downloads\AlbionMarketData"
$CsvFile      = "$OutputFolder\MarketOrders_$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

Write-Host "==================================================="
Write-Host "ALBION MARKET ORDER CAPTURE"
Write-Host "==================================================="
Write-Host ""

# --- Load items.txt mapping (numericId : stringId : DisplayName) -------------
try {
    $url = "https://raw.githubusercontent.com/ao-data/ao-bin-dumps/master/formatted/items.txt"
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    $itemsContent = $response.Content
    Write-Host "Loaded items mapping from GitHub."
} catch {
    Write-Host "Trying local items.txt file..."
    if (Test-Path ".\items.txt") {
        $itemsContent = Get-Content -Path ".\items.txt" -Raw
        Write-Host "Loaded items mapping from local file."
    } else {
        Write-Host "ERROR: Could not load items mapping!" -ForegroundColor Red
        exit 1
    }
}

$itemMapping = @{}
foreach ($line in $itemsContent -split "`n") {
    $line = $line.Trim()
    if ($line -match '^\s*\d+:\s*(\S+)\s*:\s*(.+)$') {
        $itemMapping[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}
Write-Host "Loaded $($itemMapping.Count) item names"
Write-Host ""

Write-Host "Starting capture... Press Ctrl+C to stop"
Write-Host "Output: $CsvFile"
Write-Host ""

$marketOrderCount = 0
$batchCount = 0

# Compiled regex — faster than recompiling per line.
# Finds each "{...}" entry inside the response array.
# Inside the quoted string, `\"` is an escaped quote and `\\` is an escaped backslash.
# The `(?:[^"\\]|\\.)` pattern matches "any char that isn't quote or backslash, OR a
# backslash followed by any one char" — so escaped quotes don't end the string.
$entryRegex = [regex]'"(\{(?:[^"\\]|\\.)*\})"'

# --- Main capture loop -------------------------------------------------------
& $ClientPath -debug 2>&1 | ForEach-Object {
    $line = $_

    # Match the auction-offers response line. We accept ANY numeric op ID
    # before the name (those change between expansions; the name is stable).
    # We also require an "AuctionType":"offer" hit so we skip empty responses
    # and other op variants without doing expensive regex work on every line.
    if ($line -notmatch 'OperationResponse: \[\d+\]opAuctionGetOffers') { return }
    if ($line -notmatch 'AuctionType.{1,5}offer') { return }

    $batchCount++
    Write-Host "[Batch $batchCount] Processing..." -ForegroundColor Green

    # Pull every "{...}" JSON entry out of the line. The escaped JSON strings are
    # space-separated inside `0:[ ... ]`, but we don't need to anchor to that —
    # the only place these patterns occur in the line is inside the array.
    $entries = $entryRegex.Matches($line)
    if ($entries.Count -eq 0) {
        Write-Host "  No entries matched - skipping." -ForegroundColor DarkYellow
        return
    }

    $parsedOrders = New-Object System.Collections.Generic.List[object]
    foreach ($m in $entries) {
        # Unescape: \" -> "  and  \\ -> \
        $rawJson   = $m.Groups[1].Value
        $cleanJson = $rawJson -replace '\\"', '"' -replace '\\\\', '\'

        try {
            $order = $cleanJson | ConvertFrom-Json
        } catch {
            Write-Host "  Skipping unparseable entry: $($_.Exception.Message)" -ForegroundColor DarkYellow
            continue
        }

        # Silver values are stored as integer x10000 — divide for display.
        $order.UnitPriceSilver  = [math]::Round($order.UnitPriceSilver  / 10000, 4)
        $order.TotalPriceSilver = [math]::Round($order.TotalPriceSilver / 10000, 4)

        # Look up the item name. items.txt sometimes keys items WITH the enchantment
        # suffix (e.g. T4_ROCK_LEVEL2@2) and sometimes without — depends on whether
        # the enchanted variant has its own display name. Try suffixed first, then fall
        # back to unsuffixed. The CSV always shows the unsuffixed id for consistency.
        $fullItemId  = $order.ItemTypeId
        $cleanItemId = ($fullItemId -replace '@\d+', '')
        $itemName    = if ($itemMapping.ContainsKey($fullItemId)) {
            $itemMapping[$fullItemId]
        } elseif ($itemMapping.ContainsKey($cleanItemId)) {
            $itemMapping[$cleanItemId]
        } else {
            "Unknown"
        }

        $row = [pscustomobject]@{
            ItemTypeId       = $cleanItemId
            'Item Name'      = $itemName
            Tier             = $order.Tier
            EnchantmentLevel = $order.EnchantmentLevel
            QualityLevel     = $order.QualityLevel
            Amount           = $order.Amount
            UnitPriceSilver  = $order.UnitPriceSilver
            TotalPriceSilver = $order.TotalPriceSilver
            AuctionType      = $order.AuctionType
            SellerName       = $order.SellerName
            Expires          = $order.Expires
            LocationId       = $order.LocationId
        }
        $parsedOrders.Add($row)
    }

    if ($parsedOrders.Count -eq 0) {
        Write-Host "  All entries failed to parse." -ForegroundColor DarkYellow
        return
    }

    # Append to CSV. -NoTypeInformation suppresses the #TYPE header line.
    if (-not (Test-Path $CsvFile)) {
        $parsedOrders | Export-Csv -Path $CsvFile -NoTypeInformation
    } else {
        $parsedOrders | Export-Csv -Path $CsvFile -NoTypeInformation -Append
    }

    $marketOrderCount += $parsedOrders.Count
    Write-Host "  Saved $($parsedOrders.Count) orders. Total: $marketOrderCount" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==================================================="
Write-Host "Capture stopped."
Write-Host "  Batches: $batchCount"
Write-Host "  Total orders: $marketOrderCount"
Write-Host "  CSV: $CsvFile"
Write-Host "==================================================="
