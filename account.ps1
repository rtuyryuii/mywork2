# account.ps1
$ErrorActionPreference = "Stop"

$NamesFile = Join-Path $PSScriptRoot "names.txt"
$AccountFile = Join-Path $PSScriptRoot "account.txt"

if (-not (Test-Path $NamesFile)) {
    Write-Error "Error: Source file $NamesFile does not exist!"
    exit 1
}

# 1. Randomly pick a line and extract name components (skipping header)
$lines = Get-Content $NamesFile | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" }
$randomLine = $lines | Get-Random
$cols = $randomLine -split '\s+'

# Randomly select First Name (index 0 or 1) and Last Name (index 2)
$firstName = $cols[(Get-Random -Minimum 0 -Maximum 2)]
$lastName = $cols[2]
$randomDigits = Get-Random -Minimum 100 -Maximum 999999

$rawUsername = "$($firstName.ToLower())$($lastName.ToLower())$randomDigits"
$email = "$rawUsername@outlook.com"

# 2. Generate random password (8-12 chars: starting with lowercase letter)
$passLen = Get-Random -Minimum 8 -Maximum 13
$charList = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$firstChar = ([char[]]"abcdefghijklmnopqrstuvwxyz".ToCharArray() | Get-Random).ToString()

$restChars = -join (1..($passLen - 1) | ForEach-Object { $charList | Get-Random })
$randomPass = "$firstChar$restChars"

# 3. Random birth year (1980-2005)
$birthYear = Get-Random -Minimum 1980 -Maximum 2006

# 4. Write account details into account.txt (5 lines)
@($email, $randomPass, $birthYear, $firstName, $lastName) | Set-Content -Path $AccountFile -Encoding UTF8

Write-Host "[INFO] Account data generated successfully! Content below:"
Get-Content $AccountFile
