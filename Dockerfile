<#
.SYNOPSIS
  Ensure a Key Vault secret matches a given local value.

.PARAMETER VaultName
  Name of the Key Vault.

.PARAMETER SecretName
  Name of the secret in Key Vault.

.PARAMETER DesiredValue
  The plaintext value you want stored in Key Vault.

.PARAMETER TenantId
  (Optional) Tenant ID for Service Principal auth.

.PARAMETER AppId
  (Optional) Service Principal App ID.

.PARAMETER AppSecret
  (Optional) Service Principal secret.

.EXAMPLE
  # Interactive login
  .\Sync-KvSecret.ps1 -VaultName "MyVault" -SecretName "MySecret" -DesiredValue "foo123"

  # Service Principal login
  .\Sync-KvSecret.ps1 -VaultName "MyVault" -SecretName "MySecret" `
      -DesiredValue "foo123" -TenantId $env:AZ_TENANT_ID `
      -AppId $env:AZ_APP_ID -AppSecret $env:AZ_APP_SECRET
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$VaultName,

  [Parameter(Mandatory)]
  [string]$SecretName,

  [Parameter(Mandatory)]
  [string]$DesiredValue,

  [string]$TenantId,
  [string]$AppId,
  [string]$AppSecret
)

function Connect-Azure {
  if ($TenantId -and $AppId -and $AppSecret) {
    Write-Verbose "Authenticating with Service Principal..."
    Connect-AzAccount `
      -ServicePrincipal `
      -Tenant $TenantId `
      -ApplicationId $AppId `
      -Credential (New-Object System.Management.Automation.PSCredential($AppId, (ConvertTo-SecureString $AppSecret -AsPlainText -Force)))
  }
  else {
    Write-Verbose "Authenticating interactively..."
    Connect-AzAccount -Tenant $TenantId
  }
}

function Get-ExistingSecretValue {
  param($vault, $name)

  try {
    $secret = Get-AzKeyVaultSecret -VaultName $vault -Name $name -ErrorAction Stop
    return $secret.SecretValueText
  }
  catch [Microsoft.Azure.Commands.KeyVault.Models.KeyVaultErrorException] {
    # Secret not found
    return $null
  }
}

function Ensure-Secret {
  param($vault, $name, $value)

  $current = Get-ExistingSecretValue -vault $vault -name $name

  if ($null -eq $current) {
    Write-Host "Secret '$name' does not exist. Creating it..."
    Set-AzKeyVaultSecret -VaultName $vault -Name $name -SecretValue (ConvertTo-SecureString $value -AsPlainText -Force) | Out-Null
    Write-Host "✅ Created."
  }
  elseif ($current -ne $value) {
    Write-Host "Secret '$name' exists but value differs. Updating..."
    Set-AzKeyVaultSecret -VaultName $vault -Name $name -SecretValue (ConvertTo-SecureString $value -AsPlainText -Force) | Out-Null
    Write-Host "✅ Updated."
  }
  else {
    Write-Host "Secret '$name' already up‑to‑date. No action needed."
  }
}

# --- Script start ---
Connect-Azure
Ensure-Secret -vault $VaultName -name $SecretName -value $DesiredValue
