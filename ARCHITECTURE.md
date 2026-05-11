# Architecture: Zero Trust Conditional Access Policy Set

**Built by Justin Gallimore | IAM Engineer**

---

## Overview

This document describes the full architecture of the Zero Trust Conditional Access environment built in this project. It covers the identity plane, the access control layer, the monitoring pipeline, and the alerting system. Every component is documented with its purpose, its dependencies, and how it connects to the rest of the environment.

This is not a marketing diagram. This is a technical blueprint of a real environment.

---

## Environment Summary

| Component | Value |
|-----------|-------|
| Identity Platform | Microsoft Entra ID P2 |
| Tenant Domain | justingallimoregmail.onmicrosoft.com |
| Total Users | 13 |
| Admin Account | labadmin@justingallimoregmail.onmicrosoft.com |
| Break Glass Account | breakglass@justingallimoregmail.onmicrosoft.com |
| Azure Subscription | Azure subscription 1 |
| Resource Group | rg-iam-lab |
| Region | East US |
| Log Analytics Workspace | law-iam-lab |
| Alert Rule | ALERT - Break Glass Account Sign-In Detected |
| Action Group | ag-breakglass-notify |

---

## Trust Boundary Map

```
+------------------------------------------------------------------+
|                     MICROSOFT ENTRA ID TENANT                    |
|                  justingallimoregmail.onmicrosoft.com            |
|                                                                  |
|   +------------------+        +-----------------------------+   |
|   |   13 User         |        |   Entra ID P2 Features      |   |
|   |   Accounts        |        |                             |   |
|   |                  |        |   Identity Protection        |   |
|   |   labadmin        |        |   Sign-In Risk Engine        |   |
|   |   breakglass      |        |   User Risk Engine           |   |
|   |   + 11 others     |        |   Conditional Access         |   |
|   +--------+---------+        +------------+----------------+   |
|            |                               |                     |
|            v                               v                     |
|   +---------------------------+   +-------------------+         |
|   |  SIGN-IN EVENT            |   |  CA POLICY ENGINE |         |
|   |                           |-->|                   |         |
|   |  Who is signing in?       |   |  CA001 - CA006    |         |
|   |  From where?              |   |  Evaluate every   |         |
|   |  What device?             |   |  sign-in in       |         |
|   |  What risk score?         |   |  real time        |         |
|   +---------------------------+   +-------------------+         |
|                                           |                      |
|                    +----------------------+                      |
|                    |  Grant or Block Access                      |
|                    v                                             |
|   +------------------------------------------+                 |
|   |  DIAGNOSTIC SETTINGS                      |                 |
|   |  stream-signin-logs                        |                 |
|   |                                            |                 |
|   |  Streams: AuditLogs                        |                 |
|   |           SignInLogs                       |                 |
|   |           RiskyUsers                       |                 |
|   |           UserRiskEvents                   |                 |
|   +------------------+-----------------------+                  |
|                       |                                          |
+------------------------------------------------------------------+
                        |
                        | Log stream (continuous)
                        |
                        v
+------------------------------------------------------------------+
|                     MICROSOFT AZURE                              |
|                     Azure subscription 1                         |
|                                                                  |
|   +------------------------------------------+                 |
|   |  RESOURCE GROUP: rg-iam-lab               |                 |
|   |  Region: East US                          |                 |
|   |                                            |                 |
|   |  +--------------------------------------+ |                 |
|   |  |  LOG ANALYTICS WORKSPACE             | |                 |
|   |  |  law-iam-lab                         | |                 |
|   |  |                                      | |                 |
|   |  |  Ingests: SignInLogs table           | |                 |
|   |  |           AuditLogs table            | |                 |
|   |  |           RiskyUsers table           | |                 |
|   |  |           UserRiskEvents table       | |                 |
|   |  |                                      | |                 |
|   |  |  Queried by: Azure Monitor           | |                 |
|   |  |  every 5 minutes via KQL             | |                 |
|   |  +--------------------------------------+ |                 |
|   |                                            |                 |
|   +------------------------------------------+                 |
|                        |                                         |
|                        v                                         |
|   +------------------------------------------+                 |
|   |  AZURE MONITOR ALERT RULE                 |                 |
|   |  ALERT - Break Glass Account Sign-In      |                 |
|   |                                            |                 |
|   |  Signal: Custom log search                |                 |
|   |  KQL: SigninLogs                          |                 |
|   |    | where UserPrincipalName ==           |                 |
|   |    | "breakglass@..."                     |                 |
|   |                                            |                 |
|   |  Threshold: Table rows > 0               |                 |
|   |  Frequency: Every 5 minutes              |                 |
|   |  Severity: 0 - Critical                  |                 |
|   +------------------+-----------------------+                  |
|                       |                                          |
|                        v                                         |
|   +------------------------------------------+                 |
|   |  ACTION GROUP: ag-breakglass-notify       |                 |
|   |                                            |                 |
|   |  Notification: Email                      |                 |
|   |  Recipient: JustinGallimore@gmail.com     |                 |
|   |  Subject: CRITICAL: Break Glass           |                 |
|   |           Account Sign-In Detected        |                 |
|   +------------------------------------------+                 |
|                                                                  |
+------------------------------------------------------------------+
                        |
                        v
              EMAIL TO SECURITY ENGINEER
              Within 5 minutes of sign-in
```

---

## Conditional Access Policy Layer Architecture

The six policies are not independent. They are designed as a layered stack where each one addresses a different attack surface. Together they implement Zero Trust at the identity layer.

```
SIGN-IN ATTEMPT
      |
      v
+------------------------------+
|  CA001                       |
|  Require MFA                 |  <-- Baseline. Every user. Every app.
|  All users, all cloud apps   |      No exceptions.
+------------------------------+
      |
      v
+------------------------------+
|  CA002                       |
|  Block Legacy Authentication |  <-- Closes the MFA bypass route.
|  All users, legacy clients   |      Legacy protocols cannot do MFA.
+------------------------------+
      |
      v
+------------------------------+
|  CA003                       |
|  Require Compliant Device    |  <-- Enforces device trust.
|  All users, all cloud apps   |      Unknown devices blocked.
+------------------------------+
      |
      v
+------------------------------+
|  CA004                       |
|  Step Up MFA on Sign-In Risk |  <-- Real-time risk response.
|  Medium + High risk signals  |      Suspicious sign-in = MFA challenge.
+------------------------------+
      |
      v
+------------------------------+
|  CA005                       |
|  Force Password Change on    |  <-- Compromised account response.
|  High User Risk              |      Stolen creds = mandatory reset.
+------------------------------+
      |
      v
+------------------------------+
|  CA006                       |
|  Phishing-Resistant MFA for  |  <-- Protects the most powerful accounts.
|  Privileged Roles            |      FIDO2, Windows Hello, or passkeys only.
+------------------------------+
      |
      v
   ACCESS GRANTED
```

---

## CA Policy Target Matrix

| Policy | Users | Apps | Conditions | Grant Control |
|--------|-------|------|------------|---------------|
| CA001 | All users | All cloud apps | None | Require MFA |
| CA002 | All users | All cloud apps | Legacy client apps only | Block |
| CA003 | All users | All cloud apps | None | Compliant OR Hybrid Joined device |
| CA004 | All users | All cloud apps | Sign-in risk: Medium, High | Require MFA |
| CA005 | All users | All cloud apps | User risk: High | Password change + MFA |
| CA006 | 7 privileged roles | All cloud apps | None | Phishing-resistant MFA |

---

## Privileged Roles Covered by CA006

| Role | Why It Is Targeted |
|------|--------------------|
| Global Administrator | Full tenant control |
| Privileged Role Administrator | Can assign any role to any user |
| Security Administrator | Controls security policies and alerts |
| Exchange Administrator | Full access to all mailboxes |
| SharePoint Administrator | Full access to all SharePoint sites |
| User Administrator | Can create, modify, or delete any user |
| Conditional Access Administrator | Can modify or disable CA policies |

These seven roles represent the highest blast radius if compromised. Standard push MFA is not sufficient for these accounts because of MFA fatigue attack risk. Phishing-resistant MFA only means FIDO2 security keys, Windows Hello for Business, or passkeys.

---

## Monitoring Pipeline Architecture

```
ENTRA ID SIGN-IN EVENT
         |
         | Automatic log generation
         v
DIAGNOSTIC SETTINGS (stream-signin-logs)
         |
         | Continuous streaming
         | Log categories:
         |   AuditLogs
         |   SignInLogs
         |   RiskyUsers
         |   UserRiskEvents
         v
LOG ANALYTICS WORKSPACE (law-iam-lab)
         |
         | KQL query executed every 5 minutes
         | by Azure Monitor
         v
AZURE MONITOR ALERT RULE
  Query: SigninLogs
       | where UserPrincipalName ==
       | "breakglass@justingallimoregmail.onmicrosoft.com"
         |
         | If table rows > 0
         v
ACTION GROUP (ag-breakglass-notify)
         |
         | Email notification
         v
SECURITY ENGINEER INBOX
  Subject: CRITICAL: Break Glass Account Sign-In Detected
  Delivery: Within 5 minutes of sign-in event
```

---

## RBAC Architecture

This project required navigating two separate permission systems that are commonly confused with each other.

```
+------------------------------------------+
|  MICROSOFT ENTRA ID                       |
|                                            |
|  labadmin = Global Administrator          |
|                                            |
|  Controls:                                |
|    Users, Groups, Devices                 |
|    Conditional Access Policies            |
|    Identity Protection                    |
|    Diagnostic Settings                    |
|    Entra ID License Assignment            |
|                                            |
|  Does NOT control:                        |
|    Azure subscription resources           |
|    Resource groups                        |
|    Log Analytics workspaces              |
|    Azure Monitor alert rules             |
+------------------------------------------+
              SEPARATE SYSTEM
+------------------------------------------+
|  MICROSOFT AZURE RBAC                     |
|                                            |
|  labadmin = Contributor                   |
|  (on Azure subscription 1)               |
|                                            |
|  Controls:                                |
|    Resource groups                        |
|    Log Analytics workspaces              |
|    Azure Monitor alert rules             |
|    Storage accounts                       |
|    Virtual machines                       |
|    All Azure resources                    |
|                                            |
|  Does NOT control:                        |
|    Entra ID users or groups              |
|    Conditional Access policies            |
|    Entra ID roles                         |
+------------------------------------------+
```

The Contributor role was assigned to labadmin on the Azure subscription using the Access management for Azure resources toggle in Entra Properties. This toggle was disabled immediately after use following least privilege principles.

---

## Security Design Decisions

**Why Report-only mode for all six policies?**

Report-only allows the policy engine to evaluate every sign-in and log what would have happened without blocking any actual access. In a production environment you would validate in Report-only for a defined period, review the logs for false positives, tune the policies, and then enable enforcement. Enabling untested policies directly can lock out legitimate users.

**Why OR logic instead of AND logic on CA003?**

Requiring a device to be both compliant AND hybrid joined simultaneously would block most legitimate users in a real environment since most devices are one or the other, not both. OR means either condition satisfies the requirement which matches how real enterprise device fleets are structured.

**Why is the break glass account excluded from all policies?**

The break glass account is only used when something is catastrophically wrong. If a CA policy misconfiguration locks out all administrators, the break glass account must still be able to sign in. If it were subject to the same policies it is supposed to be the escape hatch from, it loses its entire purpose.

**Why phishing-resistant MFA only for CA006 and not all users?**

Phishing-resistant MFA requires hardware like a FIDO2 security key or a device enrolled in Windows Hello for Business. Rolling this out to all users requires hardware procurement and user training. Targeting it at the seven highest privilege roles gives maximum security benefit for the accounts with the highest blast radius while remaining practical for a real deployment.

**Why disable the Access management toggle after assigning the Contributor role?**

Leaving the toggle enabled means labadmin retains User Access Administrator rights across all Azure subscriptions indefinitely. That is a broader permission than needed. Once the Contributor role was assigned the toggle served its purpose and was disabled to return to least privilege. This is the same principle applied in production PAM environments where elevated access is time-bound and revoked after use.

---

## Component Inventory

| Component | Type | Location | Purpose | Depends On |
|-----------|------|----------|---------|------------|
| labadmin | User account | Entra ID | Admin operations account | Entra ID tenant |
| breakglass | User account | Entra ID | Emergency access account | Entra ID tenant |
| CA001 | CA Policy | Entra ID | Enforce MFA for all users | Entra ID P2 |
| CA002 | CA Policy | Entra ID | Block legacy authentication | Entra ID P2 |
| CA003 | CA Policy | Entra ID | Require compliant device | Entra ID P2, Intune |
| CA004 | CA Policy | Entra ID | Step-up MFA on sign-in risk | Entra ID P2, Identity Protection |
| CA005 | CA Policy | Entra ID | Force password change on user risk | Entra ID P2, Identity Protection |
| CA006 | CA Policy | Entra ID | Phishing-resistant MFA for admins | Entra ID P2 |
| stream-signin-logs | Diagnostic Setting | Entra ID | Stream logs to Log Analytics | Entra ID P2, law-iam-lab |
| rg-iam-lab | Resource Group | Azure, East US | Container for lab resources | Azure subscription 1 |
| law-iam-lab | Log Analytics Workspace | Azure, East US | Ingest and store identity logs | rg-iam-lab |
| ALERT - Break Glass | Alert Rule | Azure Monitor | Fire on break glass sign-in | law-iam-lab, ag-breakglass-notify |
| ag-breakglass-notify | Action Group | Azure Monitor | Send email on alert trigger | Alert rule |

---

## Contact

**Justin Gallimore**
IAM Engineer
[LinkedIn](https://www.linkedin.com/in/justingallimore) | [GitHub](https://github.com/JustinGallimore)
