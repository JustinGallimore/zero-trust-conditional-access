# Walkthrough: Zero Trust Conditional Access Policy Set

**Built by Justin Gallimore | IAM Engineer**

---

## Overview

This walkthrough documents every step I took to build a production-grade Zero Trust Conditional Access policy set in a live Microsoft Entra ID tenant. Every section explains what I did, why I did it, and includes the screenshot that proves it happened. This is not a theoretical exercise. Everything in here was built, tested, and validated in a real environment.

---

## Phase 1: Environment Preparation

### Activating Entra ID P2

The tenant was running on Entra ID Free which does not support Conditional Access policies. The first thing I needed to do was activate the Entra ID P2 trial to unlock both Conditional Access and Identity Protection features.

My primary admin account was an external Microsoft Account attached to the tenant rather than a native internal cloud account. When I tried to activate the P2 trial through that account it looped through an external signup wizard without completing. This is a known behavior when the initiating account is not a native internal account.

To fix it I created a new native internal admin account called labadmin with Global Administrator rights and completed the P2 trial activation through that account via the Microsoft 365 admin center checkout flow. The trial provides 100 licenses for 30 days at no cost.

**Screenshots: 01_p2_trial_activated, 02_p2_license_active**

---

### Disabling Security Defaults

Security Defaults and Conditional Access cannot run simultaneously in the same tenant. Microsoft enforces this because they serve the same purpose but at very different levels of control. Security Defaults is a simplified one-size-fits-all baseline. Conditional Access is fully customizable policy enforcement.

I navigated to Entra admin center, Default Directory Properties, Manage Security Defaults, and set it to Disabled with the reason that the organization is planning to use Conditional Access policies.

---

### Creating the Break Glass Emergency Account

Before touching a single Conditional Access policy I created a break glass emergency account. This is a cloud-only native account with Global Administrator rights that gets permanently excluded from every CA policy in the environment.

The reason this exists is simple. If you misconfigure a Conditional Access policy and accidentally lock out all administrators, you need an escape hatch that is never subject to policy enforcement. Without a break glass account a misconfiguration can result in a complete lockout with no recovery path except a support ticket to Microsoft.

The password for this account is strong and stored offline on paper, not in a password manager or digital system, because the whole point is that it works when everything else is broken.

**Screenshot: 03_break_glass_account_created**

---

### Setting Up the Local Folder Structure

Before building any policies I created the local project folder at:

```
G:\HomeLab\IAM-Portfolio\01-conditional-access
```

With subfolders for Screenshots and Policies. This is the folder structure that maps directly to this GitHub repository.

---

## Phase 2: Building the Six Conditional Access Policies

All six policies were built from the Conditional Access blade in the Entra admin center. Every policy was set to Report-only mode, not Enabled, so they log and simulate results without enforcing. All policies exclude the break glass account, labadmin, and Justin Gallimore as safety exclusions.

**Screenshot: 04_conditional_access_overview**

---

### CA001: All Users - Require MFA

This is the baseline policy. Every other policy in this set builds on top of this one.

Scope is all users across all cloud apps. The grant control is Require multifactor authentication. No exceptions other than the permanent exclusions. This means every single sign-in across the entire tenant would require MFA before access is granted.

This policy alone closes the single most common attack vector in enterprise environments which is credential stuffing. A stolen password is worthless if MFA is enforced on every sign-in.

**Screenshots: 05_ca001_policy_configured, 06_ca001_created_successfully**

---

### CA002: All Users - Block Legacy Authentication

Legacy email protocols like Exchange ActiveSync and older mail clients do not support modern authentication challenges. This means they cannot respond to an MFA prompt. Attackers know this and deliberately use legacy protocols to bypass MFA entirely.

This policy targets the Client apps condition specifically, selecting Exchange ActiveSync clients and Other clients which are the two legacy protocol categories in Entra. The grant control is Block access with no exceptions other than the permanent exclusions.

Blocking legacy authentication is one of the highest impact single policy changes an organization can make. Microsoft's own data shows that over 99% of password spray attacks and a significant portion of credential stuffing attacks use legacy protocols.

**Screenshot: 07_ca002_created_successfully**

---

### CA003: All Users - Require Compliant Device

This policy enforces device trust as a condition of access. Scope is all users across all cloud apps. The grant control requires either a compliant Intune enrolled device OR a hybrid Entra joined device using OR logic, not AND.

The OR logic here is intentional and important. Using AND would require a device to be both compliant AND hybrid joined simultaneously, which is not how most environments work. OR means either condition satisfies the requirement which is the correct production configuration.

For this homelab environment macOS, iOS, Android, and Linux device platforms were excluded since those devices are not enrolled in the lab tenant.

**Screenshot: 08_ca003_created_successfully**

---

### CA004: All Users - Require MFA on Sign-In Risk

This policy uses Entra Identity Protection's real-time risk engine. It requires an Entra ID P2 license to function.

When Microsoft's threat intelligence detects a suspicious sign-in, it assigns a risk score of Low, Medium, or High. Common triggers include impossible travel events where a user appears to sign in from two countries within minutes of each other, sign-ins from anonymous IP addresses, and sign-ins matching known attack patterns.

This policy targets Medium and High sign-in risk. When either is detected the grant control steps up to require MFA before access is granted. A legitimate user who is actually traveling internationally will be able to complete MFA and get in. An attacker using stolen credentials who cannot complete MFA will be blocked.

**Screenshot: 09_ca004_created_policies_list**

---

### CA005: All Users - Require Password Change on High User Risk

This policy handles the scenario where Microsoft's threat intelligence flags a user account as compromised. High user risk means Microsoft has detected signals suggesting the account credentials are likely in attacker hands, such as credentials appearing in a known breach database or suspicious account behavior patterns.

When user risk hits High this policy forces a mandatory password reset combined with MFA strength requirements. The user cannot access anything in the tenant until both are completed. This immediately cuts off any attacker who may have the current credentials while forcing the legitimate user to establish new ones.

**Screenshot: 10_ca001_to_ca005_all_created**

---

### CA006: Privileged Roles - Require Phishing Resistant MFA

This is the most targeted and highest security policy in the set. It applies specifically to seven privileged directory roles:

- Global Administrator
- Privileged Role Administrator
- Security Administrator
- Exchange Administrator
- SharePoint Administrator
- User Administrator
- Conditional Access Administrator

These are the accounts with the most destructive potential if compromised. Standard push notification MFA is not sufficient for these accounts because it is vulnerable to MFA fatigue attacks where an attacker spams approval requests until the legitimate user accidentally hits approve out of frustration or confusion.

The grant control is Require authentication strength set to Phishing-resistant MFA which enforces FIDO2 security keys, Windows Hello for Business, or passkeys only. A standard Authenticator app push notification does not satisfy this requirement for these roles.

**Screenshot: 11_all_six_policies_complete**

---

## Phase 3: License Assignment and PowerShell Remediation

After all six policies were built I attempted to assign P2 licenses to all 13 users in the tenant through the Microsoft 365 admin center.

Every single user failed with the error: license assignment cannot be done for user with invalid usage location.

The root cause was that every user account had been provisioned without a usage location property. Microsoft requires this field to be set before any Microsoft 365 or Entra license can be assigned because licensing terms vary by country.

Instead of clicking through 13 accounts manually in the portal I chose to fix it with PowerShell and Microsoft Graph. This approach demonstrates engineering thinking over technician clicking and is significantly more impressive for a portfolio.

Three additional blockers came up during the PowerShell fix and all three were resolved:

The Microsoft Graph module was not installed on the machine. Fixed by running:
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

The PowerShell execution policy was set to Restricted which blocked the module from loading. Fixed by running:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

The Connect-MgGraph command failed to load the authentication module. Fixed by importing it manually first:
```powershell
Import-Module Microsoft.Graph.Authentication
```

After resolving all three blockers I connected to Microsoft Graph with labadmin and ran the bulk remediation script:

```powershell
Get-MgUser -All | ForEach-Object {
    Update-MgUser -UserId $_.Id -UsageLocation "US"
    Write-Host "Updated: $($_.DisplayName)"
}
```

All 13 users updated in a single execution. License assignment completed successfully after remediation.

**Screenshots: 12_license_assignment_usage_location_error, 13_usage_location_error_powershell_fix, 14_graph_module_installed, 15_connect_mggraph_module_load_error, 16_execution_policy_blocked_error, 17_connected_to_microsoft_graph, 18_bulk_usage_location_updated, 19_p2_licenses_being_assigned, 20_p2_licenses_assigned_all_users**

---

## Phase 4: Sign-In Log Validation

With all six policies built and all users licensed I needed to validate that the policy engine was actually evaluating sign-ins correctly.

I navigated to Conditional Access, Sign-in logs, clicked into a live sign-in event, and opened the Report-only tab. All six policies were visible by name in the evaluation results with their simulated outcomes showing what would have happened if each policy were enforced rather than in report-only mode.

This is the proof that the entire framework is wired correctly and actively evaluating every sign-in in the tenant.

**Screenshots: 21_sign_in_logs_active, 22_report_only_all_six_policies_logging**

---

## Phase 5: Bonus Feature - Break Glass Account Alert

### The Goal

The break glass account should essentially never be used. It exists only for emergencies. Any time it signs in, the security team needs to know immediately. This bonus feature builds a live monitoring alert that fires an email notification within 5 minutes of any break glass account sign-in.

---

### Step 1: Fixing Azure RBAC Permissions

To build the alert infrastructure I needed to create Azure resources including a Log Analytics workspace. This required labadmin to have Azure RBAC permissions on the Azure subscription, not just Entra ID Global Administrator rights.

When I navigated to the Azure subscription Access control IAM page to assign the Contributor role, the Add role assignment button was completely greyed out. labadmin had zero Azure role assignments.

The fix required navigating to Entra admin center, Default Directory Properties, and enabling the Access management for Azure resources toggle. This elevated labadmin to User Access Administrator across all Azure subscriptions in the tenant which then allowed the Contributor role assignment to be completed.

After assigning the Contributor role I immediately went back to Entra Properties and disabled the toggle to follow least privilege. Leaving elevated access open after use is a security risk even in a lab environment.

**Screenshots: 25_add_role_assignment_greyed_out, 26_azure_access_management_toggle_off, 27_azure_access_management_toggle_enabled, 28_add_role_assignment_now_available, 29_contributor_role_selected, 30_labadmin_contributor_member_selected, 31_assignment_type_active_permanent, 33_labadmin_contributor_role_assigned_success, 34_azure_access_management_toggle_disabled_least_privilege**

---

### Step 2: Creating the Resource Group

With permissions fixed I created the resource group rg-iam-lab in Azure subscription 1 in the East US region. This is the container that holds all the lab infrastructure.

The first attempt failed immediately with a permissions error even though the Contributor role had just been assigned. The root cause was Azure RBAC propagation delay. Role assignments do not take effect instantly. After waiting approximately 3 minutes and retrying the resource group was created successfully.

**Screenshots: 35_resource_group_permissions_error, 36_resource_group_created_success**

---

### Step 3: Creating the Log Analytics Workspace

Inside rg-iam-lab I created a Log Analytics workspace named law-iam-lab in East US. This is the destination where Entra ID sign-in logs get streamed for querying and alerting.

**Screenshots: 37_log_analytics_workspace_review, 38_log_analytics_workspace_deployed, 39_log_analytics_workspace_overview**

---

### Step 4: Streaming Entra Sign-In Logs

In the Entra admin center under Diagnostic settings I created a new diagnostic setting named stream-signin-logs. I selected four log categories to stream:

- AuditLogs
- SignInLogs
- RiskyUsers
- UserRiskEvents

The destination was set to Send to Log Analytics workspace pointing to law-iam-lab. Once saved Entra begins continuously streaming identity logs into the workspace where KQL queries can search them in near real-time.

**Screenshots: 40_diagnostic_settings_empty, 41_diagnostic_setting_configured, 42_diagnostic_setting_saved**

---

### Step 5: Building the Alert Rule

In Azure Monitor I created an alert rule with the following configuration:

Scope: law-iam-lab Log Analytics workspace

Signal: Custom log search using this KQL query:
```kql
SigninLogs
| where UserPrincipalName == "breakglass@justingallimoregmail.onmicrosoft.com"
```

Measurement:
- Measure: Table rows
- Aggregation type: Count
- Aggregation granularity: 5 minutes

Alert logic:
- Operator: Greater than
- Threshold value: 0
- Frequency of evaluation: 5 minutes

This means the alert fires any time the break glass account appears even once in a 5 minute window.

**Screenshots: 43_alert_rule_scope_selected, 44_alert_rule_kql_query_configured, 45_alert_rule_condition_configured**

---

### Step 6: Creating the Action Group

The action group ag-breakglass-notify defines what happens when the alert fires. I configured it to send an email notification to my personal email address with the subject line CRITICAL: Break Glass Account Sign-In Detected.

**Screenshots: 46_action_group_email_notification_configured, 47_action_group_created_attached_to_alert**

---

### Step 7: Finalizing the Alert Rule

Back in the alert rule Details tab I set:

- Severity: 0 - Critical
- Alert rule name: ALERT - Break Glass Account Sign-In Detected
- Description: Fires when the break glass emergency account signs in. Immediate investigation required.

**Screenshots: 48_alert_rule_details_configured, 49_alert_rule_review_summary, 50_alert_rule_created_success**

---

### Validation

After creation I navigated to Azure Monitor, Alert rules and confirmed the rule is listed as Enabled with Severity 0 - Critical, targeting law-iam-lab, using Log search as the signal type. The alert is armed and watching.

**Screenshot: 51_alert_rule_enabled_active**

---

## What This Project Demonstrates

By the end of this build the environment had:

A complete Zero Trust access control framework with six layered Conditional Access policies covering MFA enforcement, legacy authentication blocking, device compliance, real-time risk-based step-up authentication, compromised account response, and phishing-resistant MFA for privileged roles.

A break glass emergency account properly created, excluded from all policies, and actively monitored with a live KQL alert rule that fires a Critical severity email notification within 5 minutes of any sign-in.

Real production obstacles documented and resolved including P2 activation issues, bulk license assignment failures requiring PowerShell remediation, Azure RBAC permission separation from Entra ID roles, and RBAC propagation delays.

Every error made this project stronger. Every fix is documented. That is what real IAM engineering looks like.
