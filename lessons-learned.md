# Lessons Learned

## zero-trust-conditional-access

This document covers what broke during the build, what caused it, how it was fixed, and what the production equivalent would look like. These are not hypothetical scenarios. Every issue here happened in a live Entra ID tenant and required real troubleshooting to resolve.

---

## Issue 01: Entra ID P2 Trial Activation Looping for External Admin Account

**What broke:**

Attempting to activate the Entra ID P2 trial through the primary admin account caused the activation flow to loop through an external account signup wizard without ever completing. The trial never activated regardless of how many times the flow was attempted.

**Root cause:**

The primary admin account was an external Microsoft Account federated into the tenant rather than a native internal cloud account. Microsoft's trial activation flow requires the initiating account to be a native internal account in the tenant. External accounts get routed through a different activation flow that does not complete correctly for this purpose.

**How it was fixed:**

A new native internal admin account called labadmin was created directly inside the tenant. Global Administrator rights were assigned to labadmin. The Entra ID P2 trial was activated through labadmin via the Microsoft 365 admin center and completed successfully providing 100 licenses for 30 days.

**What production looks like:**

In production all administrative tasks are performed from dedicated cloud-native admin accounts that exist natively in the tenant — not personal Microsoft Accounts or external federated identities. Break glass accounts are always native internal accounts for exactly this reason. External accounts behave unpredictably across multiple Microsoft admin flows and should never be used as the primary admin identity in a tenant.

---

## Issue 02: Bulk License Assignment Failed Due to Missing Usage Location

**What broke:**

After building all six Conditional Access policies, attempting to assign P2 licenses to all 13 users through the Microsoft 365 admin center bulk assignment flow failed on every single user with the error: License assignment cannot be done for user with invalid usage location.

**Root cause:**

Every user account in the tenant had been provisioned without a usage location property set on the account object. Microsoft requires a valid usage location on every user before any Microsoft 365 or Entra license can be assigned because licensing terms and service availability vary by country and Microsoft enforces this at the account level.

**How it was fixed:**

Rather than manually clicking through 13 user accounts in the portal, PowerShell with Microsoft Graph was used to bulk remediate all accounts in a single script execution. Three additional blockers came up during the fix: the Microsoft Graph PowerShell module was not installed, the execution policy was set to Restricted blocking module imports, and the authentication submodule needed to be explicitly loaded. All three were resolved in sequence before running the bulk update:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Import-Module Microsoft.Graph.Authentication
Connect-MgGraph -Scopes "User.ReadWrite.All"
Get-MgUser -All | ForEach-Object {
    Update-MgUser -UserId $_.Id -UsageLocation "US"
}
```

All 13 users updated successfully in a single execution.

**What production looks like:**

Usage location is set at account creation time as part of the joiner provisioning workflow — typically driven by the HR system of record. When it is missing it blocks licensing across the board with no warning until someone tries to assign a license. In production this would be a required attribute in the identity schema and validated as part of the provisioning acceptance criteria before the workflow goes live.

---

## Issue 03: Add Role Assignment Greyed Out on Azure Subscription

**What broke:**

Navigating to the Azure subscription Access control IAM page to assign the Contributor role to labadmin showed both Add role assignment and Add custom role completely greyed out and unclickable. labadmin had zero Azure role assignments despite being a Global Administrator in Entra ID.

**Root cause:**

Entra ID roles and Azure RBAC roles are two completely separate permission systems. Global Administrator in Entra ID has no effect on Azure subscription resource management. Azure RBAC is controlled independently at the subscription, resource group, or resource level. This is one of the most commonly misunderstood permission boundaries in the Microsoft ecosystem.

**How it was fixed:**

Microsoft provides a specific mechanism for this scenario. In the Entra admin center under Default Directory Properties there is a toggle called Access management for Azure resources. Enabling this toggle grants the Global Administrator User Access Administrator rights across all Azure subscriptions in the tenant which unlocks role assignment. After enabling the toggle, labadmin was assigned the Contributor role on the subscription. The toggle was then immediately disabled after the assignment was complete to restore least privilege.

**What production looks like:**

In production Azure RBAC assignments are managed through a formal access request and approval process. The Access management toggle is an emergency escalation path used only when bootstrapping access for the first time or recovering from a lockout scenario. It is never left enabled as a standing configuration. Disabling it immediately after use is standard practice and reflects proper access hygiene.

---

## Issue 04: Resource Group Creation Failed Immediately After Role Assignment

**What broke:**

Immediately after the Contributor role was successfully assigned to labadmin, navigating to create a resource group returned: You do not have permissions to create resource groups under this subscription. The role assignment had just confirmed successfully in the portal.

**Root cause:**

Azure RBAC role assignments do not take effect instantly. There is a propagation delay of 1 to 5 minutes. The browser session was still carrying an authentication token issued before the Contributor role was assigned. That token did not include the new role in its claims so Azure correctly rejected the resource creation based on the permissions in the existing token.

**How it was fixed:**

Waited approximately 3 minutes for the RBAC assignment to propagate. The resource group creation succeeded on the second attempt with no other changes needed.

**What production looks like:**

This propagation delay is expected and documented by Microsoft. In production any runbook that involves assigning an Azure role and then immediately using it includes a wait step or instructs the engineer to sign out and sign back in to force a new token. This comes up regularly whenever access is granted and immediately needed during an incident or a deployment.

---

## What I Would Do Differently in Production

All user accounts would be provisioned with usage location set at creation time as a required attribute. This would be validated in the provisioning workflow before accounts are handed off to any downstream licensing process.

The Conditional Access policies would be deployed in report-only mode first for a two-week observation period to identify any legitimate traffic that would be blocked before switching to enforcement. Skipping the report-only phase in production is a common cause of unexpected lockouts.

Break glass accounts would be native internal cloud accounts from day one, excluded from all CA policies, and monitored with a KQL alert that pages the on-call team the moment one is used.

---

*Built by Justin Gallimore | [github.com/JustinGallimore](https://github.com/JustinGallimore)*
