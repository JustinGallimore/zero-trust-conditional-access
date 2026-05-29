<h2><a href="https://www.loom.com/share/14a4e740b1b54742a857d07ecba11658">VIDEO OVERVIEW OF THIS LAB</a></h2>

# Zero Trust Conditional Access Policy Set

**Built by Justin Gallimore | IAM Engineer**
[LinkedIn](https://www.linkedin.com/in/justingallimore) | [GitHub](https://github.com/JustinGallimore)

\---

## What This Project Is

This project demonstrates the end-to-end design, implementation, and validation of a Zero Trust Conditional Access policy set in a live Microsoft Entra ID P2 tenant. Every policy was built from scratch, validated in Report-only mode through sign-in log analysis, and documented to production runbook standards.

This is not a tutorial follow-along. Every decision, every error, and every fix happened in a real tenant environment with real identity data.

\---

## Environment

* Microsoft Entra ID P2 (activated via trial on a live Azure tenant)
* 13 users across multiple departments
* Security Defaults disabled in favor of full Conditional Access control
* Break glass emergency account configured and excluded from all policies
* labadmin native internal admin account used for all configuration work

\---

## Policies Built

|Policy|Scope|Grant Control|State|
|-|-|-|-|
|CA001 - All Users - Require MFA|All users, all cloud apps|Require MFA|Report-only|
|CA002 - All Users - Block Legacy Authentication|All users, legacy clients|Block|Report-only|
|CA003 - All Users - Require Compliant Device|All users, all cloud apps|Compliant or Hybrid Joined|Report-only|
|CA004 - All Users - Require MFA on Sign-In Risk|All users, Medium + High risk|Require MFA|Report-only|
|CA005 - All Users - Require Password Change on High User Risk|All users, High user risk|Password change + MFA|Report-only|
|CA006 - Privileged Roles - Require Phishing Resistant MFA|7 admin roles|Phishing-resistant MFA only|Report-only|

\---

## Real Errors Encountered and Resolved

### Error 1: Entra ID P2 Trial Activation Blocked for External Accounts

The primary admin account was an external Microsoft Account attached to the tenant rather than a native internal account. This caused the P2 trial activation to loop through the external signup wizard without completing.

**Resolution:** Created a native internal admin account (labadmin) with Global Administrator rights and activated the P2 trial through that account via the Microsoft 365 admin center checkout flow. Trial activated successfully providing 100 licenses for 30 days.

### Error 2: Bulk License Assignment Failed with Invalid Usage Location

Attempting to assign P2 licenses to all 13 users failed across every account with the error: license assignment cannot be done for user with invalid usage location.

**Root cause:** Every user account was provisioned without a usage location property set. Microsoft requires this before any Microsoft 365 or Entra license can be assigned.

**Resolution:** Instead of clicking through 13 accounts manually in the portal, used PowerShell with Microsoft Graph to bulk remediate all accounts in a single script execution. Three additional blockers were hit and resolved during this process:

* Microsoft Graph PowerShell module was not installed. Fixed with: `Install-Module Microsoft.Graph -Scope CurrentUser -Force`
* Execution policy was set to Restricted and blocked module loading. Fixed with: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
* Connect-MgGraph failed to load the module. Fixed with: `Import-Module Microsoft.Graph.Authentication` before connecting

After resolving all three, connected to Microsoft Graph and ran the following bulk remediation script:

```powershell
Get-MgUser -All | ForEach-Object {
    Update-MgUser -UserId $\\\_.Id -UsageLocation "US"
    Write-Host "Updated: $($\\\_.DisplayName)"
}
```

All 13 users updated in a single execution. License assignment completed successfully after remediation.

\---

## Validation

All six policies were validated in Report-only mode through the Conditional Access Sign-in Logs. Each sign-in event was opened and the Report-only tab was reviewed to confirm the policy engine was actively evaluating every sign-in and logging the simulated result for all six policies by name.

\---

## Bonus Feature: Break Glass Account Alert

### What It Is

A production-grade monitoring alert that fires an email notification within 5 minutes any time the break glass emergency account signs in. In a real enterprise environment, the break glass account should almost never be used. Any sign-in from it is an immediate red flag requiring investigation.

### Architecture

```
Entra ID Sign-In Logs
        |
        v
Diagnostic Settings (stream-signin-logs)
        |
        v
Log Analytics Workspace (law-iam-lab) — East US
        |
        v
Azure Monitor Alert Rule (KQL custom log search)
        |
        v
Action Group (ag-breakglass-notify) — Email to JustinGallimore@gmail.com
```

### What Was Built

**Resource Group:** rg-iam-lab in Azure subscription 1

**Log Analytics Workspace:** law-iam-lab in East US, inside rg-iam-lab

**Diagnostic Setting:** stream-signin-logs streaming AuditLogs, SignInLogs, RiskyUsers, and UserRiskEvents from Entra ID to the Log Analytics workspace

**Alert Rule:** ALERT - Break Glass Account Sign-In Detected

* Signal: Custom log search
* KQL query targeting break glass UPN in SigninLogs table
* Measure: Table rows, Count aggregation, 5 minute granularity
* Alert logic: Greater than 0, evaluated every 5 minutes
* Severity: 0 - Critical
* Action: Email notification via ag-breakglass-notify action group

**KQL Query:**

```kql
SigninLogs
| where UserPrincipalName == "breakglass@justingallimoregmail.onmicrosoft.com"
```

### Real Errors Encountered and Resolved

**Error 3: Add Role Assignment Greyed Out on Azure Subscription**

After activating the Entra ID P2 trial and creating labadmin as a Global Administrator, the Add role assignment button on the Azure subscription Access control IAM page was greyed out. labadmin had no Azure RBAC roles on the subscription despite having Global Administrator rights in Entra ID.

**Root cause:** Entra ID roles and Azure RBAC roles are two completely separate permission systems. Global Administrator in Entra does not grant the ability to manage Azure subscription resources.

**Resolution:** Navigated to Entra admin center, Default Directory Properties, and enabled the Access management for Azure resources toggle. This elevated labadmin to User Access Administrator across all Azure subscriptions in the tenant. After enabling, returned to the Azure subscription Access control IAM page, confirmed the Add role assignment button was now active, assigned labadmin the Contributor role with Active and Permanent assignment type, then returned to Entra Properties and disabled the toggle to follow least privilege.

**Error 4: Resource Group Creation Failed with Permissions Error**

After assigning the Contributor role, attempting to create the rg-iam-lab resource group immediately failed with: You do not have permissions to create resource groups under this subscription.

**Root cause:** Azure RBAC role assignments do not take effect instantly. The browser session was still carrying an authentication token issued before the Contributor role was assigned.

**Resolution:** Waited approximately 3 minutes for RBAC propagation and retried. Resource group created successfully.

\---

## Key IAM Concepts Demonstrated

* Zero Trust architecture and Conditional Access policy design
* Entra ID P2 Identity Protection with real-time risk-based access control
* MFA fatigue attack prevention via phishing-resistant MFA enforcement
* Break glass account strategy including creation, exclusion, and monitoring
* Azure RBAC vs Entra ID role separation
* KQL log queries for identity security monitoring
* Microsoft Graph PowerShell bulk remediation
* Least privilege principle applied to elevated access workflows
* Diagnostic settings and log streaming to Log Analytics

\---

## Screenshot Index

|Screenshot|Description|
|-|-|
|01\_p2\_trial\_activated|Entra ID P2 trial activation confirmed|
|02\_p2\_license\_active|P2 license active in tenant|
|03\_break\_glass\_account\_created|Break glass emergency account created|
|04\_conditional\_access\_overview|Conditional Access blade overview|
|05\_ca001\_policy\_configured|CA001 configuration details|
|06\_ca001\_created\_successfully|CA001 saved in Report-only mode|
|07\_ca002\_created\_successfully|CA002 legacy auth block policy saved|
|08\_ca003\_created\_successfully|CA003 compliant device policy saved|
|09\_ca004\_created\_policies\_list|CA004 risk-based MFA policy saved|
|10\_ca001\_to\_ca005\_all\_created|First five policies complete|
|11\_all\_six\_policies\_complete|All six CA policies created|
|12\_license\_assignment\_usage\_location\_error|Bulk license assignment error|
|13\_usage\_location\_error\_powershell\_fix|PowerShell remediation approach|
|14\_graph\_module\_installed|Microsoft Graph module installed|
|15\_connect\_mggraph\_module\_load\_error|Module load error encountered|
|16\_execution\_policy\_blocked\_error|Execution policy blocked error|
|17\_connected\_to\_microsoft\_graph|Successful Graph connection|
|18\_bulk\_usage\_location\_updated|All 13 users updated via script|
|19\_p2\_licenses\_being\_assigned|License assignment in progress|
|20\_p2\_licenses\_assigned\_all\_users|All users licensed successfully|
|21\_sign\_in\_logs\_active|Sign-in logs showing live activity|
|22\_report\_only\_all\_six\_policies\_logging|All six policies evaluating in Report-only|
|25\_add\_role\_assignment\_greyed\_out|RBAC permission error on subscription|
|26\_azure\_access\_management\_toggle\_off|Entra Properties toggle before elevation|
|27\_azure\_access\_management\_toggle\_enabled|Elevation toggle enabled|
|28\_add\_role\_assignment\_now\_available|Role assignment now accessible|
|29\_contributor\_role\_selected|Contributor role selected|
|30\_labadmin\_contributor\_member\_selected|labadmin added as member|
|31\_assignment\_type\_active\_permanent|Active Permanent assignment configured|
|32\_role\_assignment\_review\_summary|Role assignment review screen|
|33\_labadmin\_contributor\_role\_assigned\_success|Contributor role assigned successfully|
|34\_azure\_access\_management\_toggle\_disabled\_least\_privilege|Toggle disabled after use|
|35\_resource\_group\_permissions\_error|Resource group creation error|
|36\_resource\_group\_created\_success|rg-iam-lab created successfully|
|37\_log\_analytics\_workspace\_review|Log Analytics workspace review screen|
|38\_log\_analytics\_workspace\_deployed|law-iam-lab deployment complete|
|39\_log\_analytics\_workspace\_overview|Workspace overview page|
|40\_diagnostic\_settings\_empty|Diagnostic settings before configuration|
|41\_diagnostic\_setting\_configured|stream-signin-logs configured|
|42\_diagnostic\_setting\_saved|Diagnostic setting saved and active|
|43\_alert\_rule\_scope\_selected|law-iam-lab selected as alert scope|
|44\_alert\_rule\_kql\_query\_configured|KQL query validated with green checkmark|
|45\_alert\_rule\_condition\_configured|Measurement and alert logic configured|
|46\_action\_group\_email\_notification\_configured|Email notification configured|
|47\_action\_group\_created\_attached\_to\_alert|ag-breakglass-notify attached|
|48\_alert\_rule\_details\_configured|Severity 0 Critical, name and description set|
|49\_alert\_rule\_review\_summary|Final review before creation|
|50\_alert\_rule\_created\_success|Alert rule created successfully|
|51\_alert\_rule\_enabled\_active|Alert rule confirmed Enabled, Severity 0 Critical, targeting law-iam-lab, Status green|

\---

## Folder Structure

```
04-conditional-access/
├── README.md
├── Screenshots/
│   └── (50 screenshots documenting the full build)
└── Policies/
    ├── CA001\\\_All\\\_Users\\\_Require\\\_MFA.md
    ├── CA002\\\_All\\\_Users\\\_Block\\\_Legacy\\\_Authentication.md
    ├── CA003\\\_All\\\_Users\\\_Require\\\_Compliant\\\_Device.md
    ├── CA004\\\_All\\\_Users\\\_Require\\\_MFA\\\_Sign\\\_In\\\_Risk.md
    ├── CA005\\\_All\\\_Users\\\_Require\\\_Password\\\_Change\\\_High\\\_User\\\_Risk.md
    └── CA006\\\_Privileged\\\_Roles\\\_Require\\\_Phishing\\\_Resistant\\\_MFA.md
```

\---

## Contact

**Justin Gallimore**
IAM Engineer
[LinkedIn](https://www.linkedin.com/in/justingallimore) | [GitHub](https://github.com/JustinGallimore)

