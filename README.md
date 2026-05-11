# Zero Trust Conditional Access Policy Set

**Built by Justin Gallimore | IAM Engineer**
[LinkedIn](https://www.linkedin.com/in/justingallimore) | [GitHub](https://github.com/JustinGallimore)

---

## What This Project Is

This project demonstrates the end-to-end design, implementation, and validation of a Zero Trust Conditional Access policy set in a live Microsoft Entra ID P2 tenant. Every policy was built from scratch, validated in Report-only mode through sign-in log analysis, and documented to production runbook standards.

This is not a tutorial follow-along. Every decision, every error, and every fix happened in a real tenant environment with real identity data.

---

## Environment

- Microsoft Entra ID P2 (activated via trial on a live Azure tenant)
- 13 users across multiple departments
- Security Defaults disabled in favor of full Conditional Access control
- Break glass emergency account configured and excluded from all policies
- labadmin native internal admin account used for all configuration work

---

## Policies Built

| Policy | Scope | Grant Control | State |
|--------|-------|---------------|-------|
| CA001 - All Users - Require MFA | All users, all cloud apps | Require MFA | Report-only |
| CA002 - All Users - Block Legacy Authentication | All users, legacy clients | Block | Report-only |
| CA003 - All Users - Require Compliant Device | All users, all cloud apps | Compliant or Hybrid Joined | Report-only |
| CA004 - All Users - Require MFA on Sign-In Risk | All users, Medium + High risk | Require MFA | Report-only |
| CA005 - All Users - Require Password Change on High User Risk | All users, High user risk | Password change + MFA | Report-only |
| CA006 - Privileged Roles - Require Phishing Resistant MFA | 7 admin roles | Phishing-resistant MFA only | Report-only |

---

## Real Errors Encountered and Resolved

### Error 1: Entra ID P2 Trial Activation Blocked for External Accounts

The primary admin account was an external Microsoft Account attached to the tenant rather than a native internal account. This caused the P2 trial activation to loop through the external signup wizard without completing.

**Resolution:** Created a native internal admin account (labadmin) with Global Administrator rights and activated the P2 trial through that account via the Microsoft 365 admin center checkout flow. Trial activated successfully providing 100 licenses for 30 days.

### Error 2: Bulk License Assignment Failed with Invalid Usage Location

Attempting to assign P2 licenses to all 13 users failed across every account with the error: license assignment cannot be done for user with invalid usage location.

**Root cause:** Every user account was provisioned without a usage location property set. Microsoft requires this before any Microsoft 365 or Entra license can be assigned.

**Resolution:** Instead of clicking through 13 accounts manually in the portal, used PowerShell with Microsoft Graph to bulk remediate all accounts in a single script execution. Three additional blockers were hit and resolved during this process:

- Microsoft Graph PowerShell module was not installed. Fixed with: `Install-Module Microsoft.Graph -Scope CurrentUser -Force`
- Execution policy was set to Restricted and blocked module loading. Fixed with: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- Connect-MgGraph failed to load the module. Fixed with: `Import-Module Microsoft.Graph.Authentication` before connecting

After resolving all three, connected to Microsoft Graph and ran the following bulk remediation script:

```powershell
Get-MgUser -All | ForEach-Object {
    Update-MgUser -UserId $_.Id -UsageLocation "US"
    Write-Host "Updated: $($_.DisplayName)"
}
```

All 13 users updated in a single execution. License assignment completed successfully after remediation.

---

## Validation

All six policies were validated in Report-only mode through the Conditional Access Sign-in Logs. Each sign-in event was opened and the Report-only tab was reviewed to confirm the policy engine was actively evaluating every sign-in and logging the simulated result for all six policies by name.

---

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
- Signal: Custom log search
- KQL query targeting break glass UPN in SigninLogs table
- Measure: Table rows, Count aggregation, 5 minute granularity
- Alert logic: Greater than 0, evaluated every 5 minutes
- Severity: 0 - Critical
- Action: Email notification via ag-breakglass-notify action group

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

---

## Key IAM Concepts Demonstrated

- Zero Trust architecture and Conditional Access policy design
- Entra ID P2 Identity Protection with real-time risk-based access control
- MFA fatigue attack prevention via phishing-resistant MFA enforcement
- Break glass account strategy including creation, exclusion, and monitoring
- Azure RBAC vs Entra ID role separation
- KQL log queries for identity security monitoring
- Microsoft Graph PowerShell bulk remediation
- Least privilege principle applied to elevated access workflows
- Diagnostic settings and log streaming to Log Analytics

---

## Screenshot Index

| Screenshot | Description |
|------------|-------------|
| 01_p2_trial_activated | Entra ID P2 trial activation confirmed |
| 02_p2_license_active | P2 license active in tenant |
| 03_break_glass_account_created | Break glass emergency account created |
| 04_conditional_access_overview | Conditional Access blade overview |
| 05_ca001_policy_configured | CA001 configuration details |
| 06_ca001_created_successfully | CA001 saved in Report-only mode |
| 07_ca002_created_successfully | CA002 legacy auth block policy saved |
| 08_ca003_created_successfully | CA003 compliant device policy saved |
| 09_ca004_created_policies_list | CA004 risk-based MFA policy saved |
| 10_ca001_to_ca005_all_created | First five policies complete |
| 11_all_six_policies_complete | All six CA policies created |
| 12_license_assignment_usage_location_error | Bulk license assignment error |
| 13_usage_location_error_powershell_fix | PowerShell remediation approach |
| 14_graph_module_installed | Microsoft Graph module installed |
| 15_connect_mggraph_module_load_error | Module load error encountered |
| 16_execution_policy_blocked_error | Execution policy blocked error |
| 17_connected_to_microsoft_graph | Successful Graph connection |
| 18_bulk_usage_location_updated | All 13 users updated via script |
| 19_p2_licenses_being_assigned | License assignment in progress |
| 20_p2_licenses_assigned_all_users | All users licensed successfully |
| 21_sign_in_logs_active | Sign-in logs showing live activity |
| 22_report_only_all_six_policies_logging | All six policies evaluating in Report-only |
| 25_add_role_assignment_greyed_out | RBAC permission error on subscription |
| 26_azure_access_management_toggle_off | Entra Properties toggle before elevation |
| 27_azure_access_management_toggle_enabled | Elevation toggle enabled |
| 28_add_role_assignment_now_available | Role assignment now accessible |
| 29_contributor_role_selected | Contributor role selected |
| 30_labadmin_contributor_member_selected | labadmin added as member |
| 31_assignment_type_active_permanent | Active Permanent assignment configured |
| 32_role_assignment_review_summary | Role assignment review screen |
| 33_labadmin_contributor_role_assigned_success | Contributor role assigned successfully |
| 34_azure_access_management_toggle_disabled_least_privilege | Toggle disabled after use |
| 35_resource_group_permissions_error | Resource group creation error |
| 36_resource_group_created_success | rg-iam-lab created successfully |
| 37_log_analytics_workspace_review | Log Analytics workspace review screen |
| 38_log_analytics_workspace_deployed | law-iam-lab deployment complete |
| 39_log_analytics_workspace_overview | Workspace overview page |
| 40_diagnostic_settings_empty | Diagnostic settings before configuration |
| 41_diagnostic_setting_configured | stream-signin-logs configured |
| 42_diagnostic_setting_saved | Diagnostic setting saved and active |
| 43_alert_rule_scope_selected | law-iam-lab selected as alert scope |
| 44_alert_rule_kql_query_configured | KQL query validated with green checkmark |
| 45_alert_rule_condition_configured | Measurement and alert logic configured |
| 46_action_group_email_notification_configured | Email notification configured |
| 47_action_group_created_attached_to_alert | ag-breakglass-notify attached |
| 48_alert_rule_details_configured | Severity 0 Critical, name and description set |
| 49_alert_rule_review_summary | Final review before creation |
| 50_alert_rule_created_success | Alert rule created successfully |
| 51_alert_rule_enabled_active | Alert rule confirmed Enabled, Severity 0 Critical, targeting law-iam-lab, Status green |

---

## Folder Structure

```
04-conditional-access/
├── README.md
├── Screenshots/
│   └── (50 screenshots documenting the full build)
└── Policies/
    ├── CA001_All_Users_Require_MFA.md
    ├── CA002_All_Users_Block_Legacy_Authentication.md
    ├── CA003_All_Users_Require_Compliant_Device.md
    ├── CA004_All_Users_Require_MFA_Sign_In_Risk.md
    ├── CA005_All_Users_Require_Password_Change_High_User_Risk.md
    └── CA006_Privileged_Roles_Require_Phishing_Resistant_MFA.md
```

---

## Contact

**Justin Gallimore**
IAM Engineer
[LinkedIn](https://www.linkedin.com/in/justingallimore) | [GitHub](https://github.com/JustinGallimore)
