# =============================================================================
# Get_CA_Policy_Status.ps1
# Author: Justin Gallimore
# Description: Authenticates to Microsoft Graph API using an Entra ID app
#              registration and retrieves the current state of all Conditional
#              Access policies in the tenant. Flags any policies that are in
#              report-only or disabled state so they can be reviewed.
#              In a Zero Trust environment CA policies are a critical control —
#              a policy that gets accidentally disabled or left in report-only
#              mode creates a real gap in your security posture.
# =============================================================================

# -----------------------------------------------------------------------------
# CONFIGURATION
# Replace these placeholder values with your actual Entra ID app registration
# details. In production these would be stored in Azure Key Vault or pulled
# from environment variables — never hardcoded in the script.
# -----------------------------------------------------------------------------
$TenantID     = "YOUR_TENANT_ID"        # Entra ID tenant ID (found in Azure Portal under Entra ID overview)
$ClientID     = "YOUR_CLIENT_ID"        # App registration client ID
$ClientSecret = "YOUR_CLIENT_SECRET"    # App registration client secret — treat like a password

# -----------------------------------------------------------------------------
# STEP 1: AUTHENTICATE — GET AN ACCESS TOKEN FROM MICROSOFT IDENTITY PLATFORM
# We use the OAuth2 client credentials flow to get a token scoped to
# Microsoft Graph. The resource scope we need is Policy.Read.All which
# grants read access to Conditional Access policies.
# -----------------------------------------------------------------------------
Write-Host "[*] Requesting access token from Microsoft Identity Platform..." -ForegroundColor Cyan

$TokenURL = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"

$TokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $ClientID
    client_secret = $ClientSecret
    scope         = "https://graph.microsoft.com/.default"   # .default requests all permissions granted to the app registration
}

try {
    $TokenResponse = Invoke-RestMethod -Uri $TokenURL -Method POST -Body $TokenBody -ContentType "application/x-www-form-urlencoded"
    $AccessToken = $TokenResponse.access_token
    Write-Host "[+] Access token retrieved successfully." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to retrieve access token. Check your tenant ID, client ID, and client secret." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 2: BUILD THE AUTH HEADER
# Microsoft Graph requires the bearer token in the Authorization header.
# Every API call in this script will use this header object.
# -----------------------------------------------------------------------------
$Headers = @{
    Authorization = "Bearer $AccessToken"
    "Content-Type" = "application/json"
}

# -----------------------------------------------------------------------------
# STEP 3: RETRIEVE ALL CONDITIONAL ACCESS POLICIES
# The Graph API endpoint for CA policies lives under the identity namespace.
# We select only the fields we need to keep the response clean and readable.
# Required Graph permission: Policy.Read.All
# -----------------------------------------------------------------------------
Write-Host "[*] Retrieving Conditional Access policies from Microsoft Graph..." -ForegroundColor Cyan

$CAPolicyURL = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?`$select=id,displayName,state,createdDateTime,modifiedDateTime"

try {
    $CAPolicyResponse = Invoke-RestMethod -Uri $CAPolicyURL -Method GET -Headers $Headers
    $Policies = $CAPolicyResponse.value
    Write-Host "[+] Retrieved $($Policies.Count) Conditional Access policies." -ForegroundColor Green
}
catch {
    Write-Host "[-] Failed to retrieve CA policies. Verify the app registration has Policy.Read.All permission." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 4: OUTPUT POLICY STATUS TABLE
# Display all policies with their current state so we have a full picture
# of what is enabled, disabled, or sitting in report-only mode.
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host " Conditional Access Policy Status Report" -ForegroundColor Yellow
Write-Host " Tenant: $TenantID" -ForegroundColor Yellow
Write-Host " Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host ""

foreach ($Policy in $Policies) {

    # Color code the state so it is easy to spot issues at a glance
    switch ($Policy.state) {
        "enabled" {
            $StateColor = "Green"
            $StateLabel = "[ENABLED]     "
        }
        "disabled" {
            $StateColor = "Red"
            $StateLabel = "[DISABLED]    "
        }
        "enabledForReportingButNotEnforced" {
            $StateColor = "Yellow"
            $StateLabel = "[REPORT-ONLY] "
        }
        default {
            $StateColor = "Magenta"
            $StateLabel = "[UNKNOWN]     "
        }
    }

    Write-Host "$StateLabel $($Policy.displayName)" -ForegroundColor $StateColor
    Write-Host "             ID: $($Policy.id)"
    Write-Host "             Last Modified: $($Policy.modifiedDateTime)"
    Write-Host ""
}

# -----------------------------------------------------------------------------
# STEP 5: FLAG POLICIES THAT NEED ATTENTION
# Any policy that is not in "enabled" state gets surfaced here as an action item.
# Report-only is fine during testing but should never be the final state in
# a production environment — it means the policy exists but is not enforcing.
# -----------------------------------------------------------------------------
$PoliciesNeedingReview = $Policies | Where-Object { $_.state -ne "enabled" }

if ($PoliciesNeedingReview.Count -gt 0) {
    Write-Host "=============================================" -ForegroundColor Red
    Write-Host " ACTION REQUIRED: Policies Not Fully Enforced" -ForegroundColor Red
    Write-Host "=============================================" -ForegroundColor Red
    foreach ($Policy in $PoliciesNeedingReview) {
        Write-Host " [-] $($Policy.displayName) is currently: $($Policy.state)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host " Review these policies and confirm the state is intentional." -ForegroundColor Yellow
}
else {
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host " All Conditional Access policies are ENABLED." -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
}
