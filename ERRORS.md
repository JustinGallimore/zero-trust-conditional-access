# Errors Encountered and Resolved

**Zero Trust Conditional Access Policy Set**
**Built by Justin Gallimore | IAM Engineer**

---

This document is a dedicated record of every real error encountered during this project, the root cause of each one, and exactly how it was resolved. These are not hypothetical scenarios. Every error here happened in a live tenant environment and required real troubleshooting to get past.

This is one of the most valuable parts of the portfolio because it proves the ability to troubleshoot, not just follow steps.

---

## Error 1: Entra ID P2 Trial Activation Looping for External Admin Account

**Where it happened:** Phase 1, during P2 trial activation

**What happened:**

Attempting to activate the Entra ID P2 trial through the primary admin account caused the flow to loop through an external account signup wizard without completing. The trial never activated.

**Root cause:**

The primary admin account was an external Microsoft Account federated into the tenant rather than a native internal cloud account. Microsoft's trial activation flow requires the initiating account to be a native internal account in the tenant. External accounts get routed through a different flow that does not complete correctly for this purpose.

**Resolution:**

Created a new native internal admin account called labadmin directly inside the tenant with a domain of justingallimoregmail.onmicrosoft.com. Assigned Global Administrator rights to labadmin. Activated the Entra ID P2 trial through labadmin via the Microsoft 365 admin center checkout flow. Trial activated successfully providing 100 licenses for 30 days.

**Lesson:**

When working with Microsoft trials and licensing in a tenant, always initiate from a native internal account. External accounts and guest accounts will behave differently than expected across multiple Microsoft admin flows.

**Screenshot:** 01_p2_trial_activated

---

## Error 2: Bulk License Assignment Failed - Invalid Usage Location

**Where it happened:** Phase 3, during P2 license assignment to tenant users

**What happened:**

After building all six Conditional Access policies, attempted to assign P2 licenses to all 13 users in the tenant through the Microsoft 365 admin center bulk assignment flow. Every single user failed with the error:

```
License assignment cannot be done for user with invalid usage location.
```

**Root cause:**

Every user account in the tenant had been provisioned without a usage location property set on the account object. Microsoft requires a valid usage location on every user account before any Microsoft 365 or Entra license can be assigned. This is because Microsoft 365 licensing terms and service availability vary by country and Microsoft enforces this at the account level before assignment.

**Resolution:**

Rather than manually clicking through 13 user accounts in the portal to set usage location one by one, used PowerShell with Microsoft Graph to bulk remediate all accounts in a single script execution.

Three additional blockers came up during the PowerShell fix:

**Blocker 2a: Microsoft Graph PowerShell module not installed**

The machine did not have the Microsoft Graph PowerShell module. Running Connect-MgGraph failed immediately.

Fix:
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

**Blocker 2b: PowerShell execution policy set to Restricted**

After installing the module, attempting to import it failed because the execution policy on the machine was set to Restricted which blocks loading of any external modules.

Fix:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Blocker 2c: Connect-MgGraph failed to load authentication module**

After updating the execution policy, Connect-MgGraph still failed because the authentication submodule was not loaded into the session automatically.

Fix:
```powershell
Import-Module Microsoft.Graph.Authentication
```

After resolving all three blockers, connected to Microsoft Graph with labadmin using:
```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All"
```

Then ran the bulk remediation script:
```powershell
Get-MgUser -All | ForEach-Object {
    Update-MgUser -UserId $_.Id -UsageLocation "US"
    Write-Host "Updated: $($_.DisplayName)"
}
```

All 13 users updated successfully in a single execution. License assignment completed with no further errors.

**Lesson:**

Always set usage location when provisioning user accounts. In production environments this is typically handled by the HR system integration or the identity provisioning tool during the joiner process. When it is missing it will block licensing across the board. PowerShell bulk remediation is always faster and more impressive than manual portal clicks when the fix needs to apply to multiple accounts.

**Screenshots:** 12_license_assignment_usage_location_error, 13_usage_location_error_powershell_fix, 14_graph_module_installed, 15_connect_mggraph_module_load_error, 16_execution_policy_blocked_error, 17_connected_to_microsoft_graph, 18_bulk_usage_location_updated

---

## Error 3: Add Role Assignment Greyed Out on Azure Subscription

**Where it happened:** Phase 5, during break glass alert infrastructure setup

**What happened:**

Navigated to the Azure subscription 1 Access control IAM page to assign the Contributor role to labadmin so it could create Azure resources. Both Add role assignment and Add custom role were completely greyed out and unclickable. The role assignments table showed No results meaning labadmin had zero Azure role assignments.

**Root cause:**

Entra ID roles and Azure RBAC roles are two completely separate permission systems that operate independently of each other. labadmin had Global Administrator rights in Entra ID but that role has no effect on Azure subscription resource management. Azure RBAC is controlled separately at the subscription, resource group, or resource level and must be assigned independently.

This is one of the most commonly misunderstood permission boundaries in the Microsoft ecosystem. Many engineers assume Global Admin in Entra means full access everywhere in Azure. It does not.

**Resolution:**

Microsoft provides a specific mechanism for this exact situation. In the Entra admin center under Default Directory Properties there is a toggle called Access management for Azure resources. Enabling this toggle grants the Global Administrator User Access Administrator rights across all Azure subscriptions in the tenant which then allows role assignments to be made.

Steps taken:

1. Navigated to Entra admin center, Default Directory Properties
2. Scrolled to Access management for Azure resources
3. Screenshotted the toggle in the Off state for documentation
4. Enabled the toggle and clicked Save
5. Returned to the Azure subscription Access control IAM page
6. Confirmed Add role assignment was now clickable
7. Assigned labadmin the Contributor role with Active and Permanent assignment type
8. Returned to Entra Properties and disabled the toggle immediately after

The toggle was disabled after use intentionally. Leaving elevated access enabled after the task is complete violates least privilege principles. Even in a lab environment, practicing proper access hygiene is important.

**Lesson:**

Entra ID roles and Azure RBAC roles are separate systems. Global Admin in Entra does not equal subscription owner in Azure. When you need to assign Azure roles and cannot, check whether the initiating account has the appropriate Azure RBAC role on the target subscription. The Access management toggle in Entra Properties is the correct escalation path for a Global Administrator who needs to bootstrap their own Azure access.

**Screenshots:** 25_add_role_assignment_greyed_out, 26_azure_access_management_toggle_off, 27_azure_access_management_toggle_enabled, 28_add_role_assignment_now_available, 33_labadmin_contributor_role_assigned_success, 34_azure_access_management_toggle_disabled_least_privilege

---

## Error 4: Resource Group Creation Failed with Permissions Error Immediately After Role Assignment

**Where it happened:** Phase 5, immediately after assigning the Contributor role to labadmin

**What happened:**

After successfully assigning the Contributor role to labadmin on Azure subscription 1, immediately navigated to create a resource group named rg-iam-lab. The creation failed with:

```
You do not have permissions to create resource groups under subscription b56cee67-d5f0-4309-b356-09c86b590ea2.
```

This was confusing because the role assignment had just completed successfully and confirmed in the portal.

**Root cause:**

Azure RBAC role assignments do not take effect instantly. There is a propagation delay that typically ranges from 1 to 5 minutes. The browser session was still carrying an authentication token that was issued before the Contributor role was assigned. That old token did not include the new role in its claims so Azure correctly rejected the resource creation attempt based on the permissions encoded in the existing token.

**Resolution:**

Waited approximately 3 minutes to allow the RBAC assignment to propagate across Azure's backend systems. Retried the resource group creation. It succeeded on the second attempt without any other changes needed.

**Lesson:**

Azure RBAC propagation is not instant. After assigning any Azure role, wait 2 to 5 minutes before attempting to use the new permissions. If the error persists after waiting, signing out and signing back in forces a new token to be issued that will include the newly assigned role. This behavior is expected and documented by Microsoft and comes up regularly in production environments when access is granted and immediately needed.

**Screenshots:** 35_resource_group_permissions_error, 36_resource_group_created_success

---

## Summary

| Error | Root Cause | Resolution |
|-------|------------|------------|
| P2 trial activation looping | External Microsoft Account used instead of native internal account | Created native labadmin account, activated trial through it |
| Bulk license assignment failed | Usage location not set on any user accounts | PowerShell Microsoft Graph bulk remediation script across all 13 users |
| Add role assignment greyed out | Entra ID Global Admin does not grant Azure RBAC permissions | Enabled Access management toggle in Entra Properties, assigned Contributor, disabled toggle |
| Resource group creation failed after role assignment | Azure RBAC propagation delay, old token still in use | Waited 3 minutes for propagation, retried successfully |

Every one of these errors is a real scenario that comes up in production IAM and Azure environments. Knowing how to recognize them, understand the root cause, and apply the correct fix is what separates engineers who have actually done the work from those who have only read about it.
