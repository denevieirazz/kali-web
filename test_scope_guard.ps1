function IpToLong([string]$ip) {
    $octets = $ip.Split('.') | ForEach-Object { [int]$_ }
    return ($octets[0] -shl 24) -bor ($octets[1] -shl 16) -bor ($octets[2] -shl 8) -bor $octets[3]
}

function IsIpInCidr([string]$ip, [string]$cidr) {
    $parts = $cidr.Split('/')
    $range = $parts[0]
    $bits = [int]$parts[1]
    $mask = (-bnot ([math]::Pow(2, 32 - $bits) - 1)) -band 0xFFFFFFFF
    $ipLong = IpToLong $ip
    $rangeLong = IpToLong $range
    return ($ipLong -band $mask) -eq ($rangeLong -band $mask)
}

function ValidateTargetAgainstScope([string]$target, $scopes) {
    if ([string]::IsNullOrWhiteSpace($target)) { return @{ allowed = $false; reason = "Target inválido." } }
    if ($null -eq $scopes -or $scopes.Count -eq 0) { return @{ allowed = $false; reason = "Nenhum escopo autorizado." } }

    $cleanTarget = $target.Trim().ToLower()

    foreach ($scope in $scopes) {
        $scopeTarget = $scope.target.Trim().ToLower()
        if ($scope.type -eq "wildcard") {
            $baseDomain = $scopeTarget -replace '^\*\.?', ''
            if ($cleanTarget -eq $baseDomain -or $cleanTarget.EndsWith(".$baseDomain")) {
                return @{ allowed = $true }
            }
        } elseif ($scope.type -eq "domain" -or $scope.type -eq "ip") {
            if ($cleanTarget -eq $scopeTarget) {
                return @{ allowed = $true }
            }
        } elseif ($scope.type -eq "cidr") {
            if ($cleanTarget -match '^\d{1,3}(\.\d{1,3}){3}$' -and (IsIpInCidr $cleanTarget $scopeTarget)) {
                return @{ allowed = $true }
            }
        }
    }
    return @{ allowed = $false; reason = "Target $target não está no escopo autorizado." }
}

$scopes = @(
    @{ target = "example.com"; type = "domain" },
    @{ target = "*.example.com"; type = "wildcard" },
    @{ target = "192.168.1.0/24"; type = "cidr" },
    @{ target = "10.0.0.5"; type = "ip" }
)

$tests = @(
    @{ name = "1. Domain Match (example.com)"; target = "example.com"; expected = $true },
    @{ name = "2. Subdomain Wildcard (sub.example.com)"; target = "sub.example.com"; expected = $true },
    @{ name = "3. Evil Domain Suffix Attack (evil-example.com)"; target = "evil-example.com"; expected = $false },
    @{ name = "4. CIDR In-Range (192.168.1.15)"; target = "192.168.1.15"; expected = $true },
    @{ name = "5. CIDR Out-of-Range (192.168.2.15)"; target = "192.168.2.15"; expected = $false },
    @{ name = "6. Exact IP Match (10.0.0.5)"; target = "10.0.0.5"; expected = $true },
    @{ name = "7. Unmatched IP (10.0.0.6)"; target = "10.0.0.6"; expected = $false }
)

$allPassed = $true
foreach ($t in $tests) {
    $res = ValidateTargetAgainstScope $t.target $scopes
    $pass = ($res.allowed -eq $t.expected)
    if (-not $pass) { $allPassed = $false }
    $statusText = if ($pass) { "PASS" } else { "FAIL" }
    Write-Host "[$statusText] $($t.name) -> Result: $($res.allowed), Expected: $($t.expected)"
}

if ($allPassed) {
    Write-Host "`n✅ TODOS OS TESTES DE ALGORITMO DO SCOPE GUARD PASSARAM COM SUCESSO!" -ForegroundColor Green
} else {
    Write-Error "FALHA NOS TESTES DE SCOPE GUARD"
}
