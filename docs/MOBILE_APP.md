# OWRTPC Mobile: deferred specifications

Status: agreed direction, development deferred at the user's request.
Recorded on 2026-08-26. This is a planning note, not an implemented feature
or a commitment to a delivery date. Resume only when requested.

## Purpose and platforms

Provide a convenient open-source companion interface for both Android and iOS.
Support OpenWrt routers running OWRTPC, without requiring a Flint2 or GL.iNet
firmware. Treat both platforms as first-class targets.

Flutter is the proposed implementation framework, with a shared codebase.
Validate platform-specific navigation, accessibility and permissions on both
Android and iOS before committing to the implementation.

## Project boundaries

- Keep the router engine, APIs and LuCI interface in
  `owrtpc/owrt-parental-control`.
- Plan a separate `owrtpc-mobile` repository under the OWRTPC organization.
  Repository creation and app scaffolding are deferred.
- The router remains the source of truth for configuration, usage, quotas and
  enforcement. The app must not duplicate the parental-control engine.
- LuCI must remain usable independently of the mobile app.
- The initial version connects to a router on the local network.
- Remote connectivity, VPN selection and cloud access are explicitly deferred.

## Initial screens

1. **Connection:** router address and authentication, with clear handling of
   connection failures, expired sessions and required local-network permissions.
2. **Profiles:** mobile-friendly cards showing profile state, used time and
   remaining time instead of the wide LuCI table.
3. **Quick actions:** Block/Unblock, Enable/Disable, and +1h, +4h or All Day,
   with visible success or failure confirmation.
4. **Profile editor:** device assignment, weekday/weekend allowances and
   bedtime schedules, clearly distinguishing pending edits from applied changes.

## Behavior to preserve

- Each device belongs to at most one profile.
- Usage remains cumulative across devices within each profile.
- Quick actions are immediate; configuration editing must clearly indicate
  when changes are pending and when they have been applied on the router.
- The latest extra-time choice replaces the previous choice. Bedtime retains
  priority over extra time, which does not carry into a later budget.
- A disabled profile must not enforce parental-control restrictions.

## Privacy and distribution

No mandatory cloud account, no telemetry by default, and no credentials stored
in plain text. Define safe authentication, credential storage, permissions and
transport/certificate handling before implementation; local access is not a
reason to ignore these requirements.

Flutter does not remove Apple or Google distribution requirements.
Store publication, signing arrangements, supported OS versions and the mobile
repository license still need to be decided. A web app remains an alternative
if avoiding store distribution becomes a priority.

## Where to resume

1. Review the existing OWRTPC APIs and define a documented, versioned contract,
   including authentication, permissions and configuration-apply semantics.
2. Define the screen flow and shared interaction rules, with platform-specific
   adaptations where useful.
3. Confirm the framework and distribution approach, then create the separate
   mobile repository and plan the implementation.
