# Connect the mobile app securely

The current mobile source supports API major 1. Full profile management in
mobile 0.4.x requires the capabilities provided by backend 0.4.0-r3 (API 1.6).
That backend release is currently a draft, and mobile store/device acceptance
is still open. Use [the release roadmap](ROADMAP.md) for publication status;
source compatibility does not mean an app binary is publicly available.

## Prepare the router

Install the backend using [INSTALL.md](INSTALL.md), retaining a configuration
backup and the previous signed packages. LuCI is optional. The mobile transport
requires `uhttpd`, `uhttpd-mod-ubus`, a TLS provider supported by the firmware,
and an HTTPS certificate/key. An existing working LuCI HTTPS installation can
provide that transport. OWRTPC itself does not install or expose a web server.
On a headless installation, configure the firmware's HTTPS service first;
installing `uhttpd-mod-ubus` alone does not establish working TLS.

Keep an authenticated SSH session open while adjusting the web service. Review
`/etc/config/uhttpd`: the selected instance needs an HTTPS listener on the
trusted LAN address, the correct `cert` and `key` paths, `ubus_prefix '/ubus'`,
and `no_ubusauth '0'`. Retain authentication. Keep WAN and untrusted/guest
access blocked, including IPv6; do not create a port forward for the app.
If several web-server instances exist, change only the instance serving the
phone's router address. Back up its configuration before applying changes.

The app address is the HTTPS router origin, for example
`https://192.168.1.1` (replace this with your actual LAN address), with a port
when needed. Do not enter a LuCI page URL. The app uses `/ubus` itself.
Connect the phone to a network permitted to reach that listener and grant the
app local-network access when the operating system requests it.

Software and hardware flow offloading must both be disabled for OWRTPC traffic
accounting. In LuCI, inspect **Network > Firewall > General Settings**. Firmware
with a separate acceleration feature requires its vendor-specific check too.
Verify `owrtpcctl validate`, `owrtpcctl status` and `owrtpcctl diagnostics` after
the change. See [the accounting limitation](ARCHITECTURE.md#flow-offloading).

## Compare the HTTPS certificate fingerprint

Obtain the certificate from a channel you already trust: the router console or
an SSH connection whose host identity has already been verified. Looking at the
certificate from the same unverified HTTPS connection is not an independent
comparison. The HTTPS certificate is different from the APK release signing key.

Find the certificate path for the correct uhttpd instance, for example:

```sh
uci -q get uhttpd.main.cert
```

With OpenSSL available on the router, use the actual returned path:

```sh
openssl x509 -in /etc/uhttpd.crt -noout -sha256 -fingerprint
```

Some firmware stores the certificate in DER format. If PEM parsing fails, use:

```sh
openssl x509 -inform DER -in /etc/uhttpd.crt -noout -sha256 -fingerprint
```

Alternatively copy only the public certificate over the trusted SSH connection
and run OpenSSL on your computer. Do not copy the private key. Compare the full
SHA-256 fingerprint with the pairing screen before accepting a self-signed
certificate. A mismatch means stop and inspect the address and router identity.

The app first uses normal operating-system certificate validation. Explicit
pairing is required for an unknown self-signed identity. A changed stored
fingerprint blocks login. After a deliberate certificate renewal, obtain and
compare the new fingerprint through the trusted channel before pairing again;
never accept an unexpected replacement merely to dismiss the error.

## Create an account limited to OWRTPC

Use a separate rpcd login instead of sharing the router administrator password.
This account is for the mobile API and does not require a Unix/SSH account.
Generate a unique password in a password manager. On a trusted system with
OpenSSL supporting SHA-512 password hashes, run `openssl passwd -6` and enter
the password at its prompt. Keep the resulting hash private too.

Back up `/etc/config/rpcd`, then add one new login section using an editor:

```uci
config login 'owrtpc_mobile'
        option username 'owrtpc-mobile'
        option password 'REPLACE_WITH_THE_GENERATED_PASSWORD_HASH'
        list read 'owrtpc'
```

Replace the entire placeholder with the generated hash, preserving single
quotes. Leave existing administrator sections intact. Do not use an empty
password, a shared example password, `$p$root`, or wildcard grants. This is
initially a read-only account. To allow this user to manage profiles, add:

```uci
        list write 'owrtpc'
```

The write grant includes OWRTPC quick actions, profile transactions and reset
of **all OWRTPC data**. It does not grant firewall/network configuration writes.
The read grant includes profiles, device discovery and relevant configuration
reads; it is not an account restricted to one child's profile. See the exact
[backend ACL](../owrtpc/files/usr/share/rpcd/acl.d/owrtpc.json).

Protect `/etc/config/rpcd` with owner-only permissions, save the file, and restart
rpcd during a maintenance window. Existing web/mobile sessions may end:

```sh
chmod 0600 /etc/config/rpcd
/etc/init.d/rpcd restart
```

Sign in with the new account. Confirm profiles are visible and, for a read-only
account, that all write controls are absent. Sign out and in again after changing
permissions. Backend ACL checks and the app's capability checks are both required;
a feature advertised by the router is not permission to use it.

## Compatibility and acceptance

| Backend capability | Current mobile behavior |
| --- | --- |
| No `owrtpc-mobile` API, or unsupported major | Connection is incompatible; update using a supported matching release |
| API major 1 without a particular transaction feature | That profile mutation is unavailable; no fallback to generic UCI writes |
| `profile-edit-transaction` / API 1.3 | Existing-profile editing, subject to account permissions |
| `profile-create-transaction` / API 1.4 | Profile creation, subject to account permissions |
| `profile-delete-transaction` / API 1.5 | Profile deletion, subject to account permissions |
| `profile-order-transaction` / API 1.6 | Complete-list transactional ordering, subject to account permissions |

Feature flags and session permissions control availability; version strings
alone do not. Install matching backend/LuCI packages from one release, backend
first. A GitHub core `.apk` is an OpenWrt package, not an Android app installer.
For upgrade/migration failures, follow [installation and recovery](INSTALL.md).
Do not reset OWRTPC as a connectivity troubleshooting step.

Before public delivery, record the exact core/mobile source SHA, installed
versions/builds, router firmware and phone OS in the
[physical acceptance issue](https://github.com/owrtpc/mobile/issues/2). Exercise
read-only and write accounts, certificate mismatch, denied local access,
disconnect/reconnect, session renewal, conflicting edits and profile ordering.
Check policy enforcement and counters on the router, and launch the signed app
from the phone's Home screen. Automated tests do not close these device checks.

## Upstream references

- [OpenWrt 25.12 uhttpd configuration](https://github.com/openwrt/openwrt/blob/openwrt-25.12/package/network/services/uhttpd/files/uhttpd.config)
- [OpenWrt HTTPS startup and certificate generation](https://github.com/openwrt/openwrt/blob/openwrt-25.12/package/network/services/uhttpd/files/uhttpd.init)
- [rpcd password and ACL implementation](https://github.com/openwrt/rpcd/blob/master/session.c)
