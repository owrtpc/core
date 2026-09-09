# Use OWRTPC through an external VPN

OWRTPC connects to your router over HTTPS. At home, use its trusted local
network. Away from home, first establish a VPN that makes the same HTTPS
service reachable, then open OWRTPC and connect normally.

VPN implementation and configuration are outside OWRTPC's scope. The app does
not install a VPN, create keys, change router networking, sign in to a VPN
provider or activate a tunnel. Your phone or network environment must supply
that connection; a separate VPN client may be necessary. This guide does not
promise VPN access without a client or managed network setup.

## Choose the documented path

Use **WireGuard on OpenWrt first** when your home connection allows incoming
VPN traffic. Consider **Tailscale** if direct access is impractical, for example
because of carrier-grade NAT (CGNAT) without usable inbound IPv6. Tailscale can
traverse NAT or relay encrypted traffic when a direct path is unavailable.
See [Tailscale connection types](https://tailscale.com/docs/reference/connection-types).

WireGuard is free software and needs no provider account. Tailscale's Personal
plan is for non-commercial use; check current terms for your use case. These
are external choices, not OWRTPC subscriptions. See
[WireGuard](https://www.wireguard.com/) and
[Tailscale plans](https://tailscale.com/pricing).

## WireGuard: prepare outside OWRTPC

Ask the router administrator to complete these steps while local access to
the router is available:

1. Check whether the home router can receive VPN traffic. A changing public IP
   can use DDNS; DDNS does not remove CGNAT. A second router upstream may need
   a UDP port forward for WireGuard.
2. Follow the official [OpenWrt WireGuard server guide](https://openwrt.org/docs/guide-user/services/vpn/wireguard/server).
   LuCI support is provided by `luci-proto-wireguard`. Use packages matching
   the installed firmware, back up its configuration, and retain local access.
3. Create a separate peer for each phone. Import its configuration using the
   external client's supported secure transfer or QR workflow. Treat the
   configuration and QR code as secrets; revoke that peer if the phone is lost.
   [Official clients](https://www.wireguard.com/install/) include iOS and Android.
4. Route the router's HTTPS address through the tunnel and allow only the
   required access from the authenticated VPN peer. For a service on OpenWrt
   itself this is router input traffic, not simply forwarding to LAN devices.
   Keep management HTTPS and `/ubus` inaccessible from the public WAN.
5. If using a router hostname, configure DNS that works through the tunnel.
   Otherwise use the routed IP address. `openwrt.lan` does not automatically
   resolve away from home. OpenWrt documents [DDNS and VPN DNS](https://openwrt.org/docs/guide-user/services/vpn/wireguard/extras).
6. Configure [the HTTPS firewall input rule](#allow-https-to-the-router-itself)
   to allow access to the router itself.

> Only traffic needed to reach the router must use the VPN; sending all phone
> Internet traffic through home is not an OWRTPC requirement. Network/firewall
> values depend on your installation, so do not copy another router's addresses.

### Allow HTTPS to the router itself

A successful WireGuard handshake does not grant access to the router's web
service. If the VPN firewall zone rejects input, explicitly allow the required
HTTPS ports. In LuCI, open **Network > Firewall > Traffic Rules** and create
the rule below, or edit the existing HTTPS rule rather than adding a duplicate.

This example uses VPN zone `wgserver`, phone tunnel address `10.1.0.2`, router
LAN address `192.168.8.1`, and HTTPS ports `443` and `8443`. Replace the zone,
addresses and ports with your actual configuration. On the verified Flint2,
`443` serves the GL.iNet interface and `8443` serves uhttpd with `/ubus` for
OWRTPC. Only permit the ports you need; other installations may use one port.

| LuCI field | Example value |
| --- | --- |
| Name | HTTPS access to router from VPN |
| Protocol | TCP |
| Source zone | `wgserver` |
| Source address | `10.1.0.2/32` |
| Destination zone | **Device (input)** / **This device**, depending on the LuCI translation |
| Destination address | `192.168.8.1` |
| Destination ports | `443 8443` |
| Action | Accept |
| Address family | IPv4 |
| Enabled | Yes |

**Do not select `lan` as the destination zone.** Even though `192.168.8.1`
is the router's LAN address, packets addressed to the router itself use INPUT.
A rule with destination zone `lan` applies to forwarded traffic to LAN devices
and will not authorize this connection. To correct that mistake, change the
existing rule's destination zone to **Device (input)**, retaining its
destination IP, source restriction and HTTPS ports. Then **Save & Apply**.

The equivalent `/etc/config/firewall` section is shown for reference. There is
deliberately **no `option dest`**: `dest_ip` selects the router address without
turning the rule into a forwarding rule.

```uci
config rule 'vpn_router_https'
        option name 'HTTPS access to router from VPN'
        option src 'wgserver'
        option src_ip '10.1.0.2/32'
        option dest_ip '192.168.8.1'
        option proto 'tcp'
        option dest_port '443 8443'
        option family 'ipv4'
        option target 'ACCEPT'
        option enabled '1'
```

In the **phone's WireGuard peer configuration**, `AllowedIPs` must include
`192.168.8.1/32`, or a larger range containing that address. Adding a route
for the router's own address on the router does not configure the phone's
route. Keep the server peer's allowed address limited to that phone's tunnel
IP (`10.1.0.2/32` in this example).

After applying, the router administrator can inspect the active rule with:

```sh
nft list chain inet fw4 input_wgserver
```

Substitute the actual VPN zone in the chain name. The HTTPS acceptance rule
must appear before the final reject; finding it only in `forward_wgserver`
indicates the wrong destination zone. With home Wi-Fi off and the VPN active,
test `https://192.168.8.1:8443` in OWRTPC using the example above. HTTPS access
does not imply ping access: this rule does not permit ICMP.

Leave public-WAN HTTPS administration disabled. In GL.iNet, **HTTPS Remote
Access** under administration/WAN settings is different from permission to
reach the router through the VPN. Broad VPN-to-LAN access is not required for
this limited router-management rule.

## Tailscale: alternative outside OWRTPC

1. Set up the external Tailscale software on the router or a trusted home
   gateway and on the phone. Authenticate them into the intended private
   network using the provider's setup instructions.
2. To keep using the router's LAN address in OWRTPC, configure a subnet router
   to advertise the needed route, approve it, and restrict access to the router's
   HTTPS service. Route approval and access rules are separate requirements.
   Follow [the subnet-router guide](https://tailscale.com/docs/features/subnet-routers).
3. If instead using the router's own Tailscale address, confirm that HTTPS
   listens on that address and is permitted by both access policies and the
   router firewall. Tailscale login does not configure the OWRTPC HTTPS service.
4. Connect the phone's external client and verify the selected HTTPS address
   before opening OWRTPC. An exit node is not required for router management.

## Connect in OWRTPC

Use the setup screen's router address field. For example, if your VPN routes
the home router at `192.168.8.1` and its HTTPS port is `8443`, enter
`https://192.168.8.1:8443`. Replace both values with your installation's values.
The public/DDNS address used by the WireGuard client to establish its tunnel
is not normally the private HTTPS address entered in OWRTPC.

Prefer the same HTTPS host and port at home and remotely where your network
allows it. Certificate pairing is scoped to that exact host and port. A
different VPN address is a different pairing endpoint, even on the same router.
Follow [certificate comparison and account setup](MOBILE_SETUP.md) before
accepting an unknown certificate. A VPN does not bypass HTTPS checks, remove
the need for the OWRTPC account, or justify accepting a changed fingerprint.

The app supports one saved router endpoint; it does not automatically switch
between separate LAN and VPN addresses.

## If the connection fails

| Symptom | What to check outside OWRTPC |
| --- | --- |
| VPN says connected but OWRTPC cannot reach the router | Route to the exact HTTPS IP, listener/port and VPN/router firewall permissions; tunnel status alone is insufficient |
| HTTPS rule exists but the router is still unreachable | Check that its destination zone is **Device (input)**, not `lan`, and that Save & Apply installed it in the VPN input chain |
| IP works but hostname fails | DNS resolution through the VPN |
| Works on mobile data but fails on another Wi-Fi | Overlapping address ranges, route selection or that network's VPN restrictions |
| Tailscale connects but LAN address fails | Advertised/approved route and access policies |
| Certificate error | Correct endpoint, clock and independently verified certificate; do not disable TLS verification |
| Login fails after network recovery | Router credentials, account ACLs and session renewal; VPN authentication is separate |

If a write is interrupted, reconnect and refresh the router state before
deciding whether another action is needed. OWRTPC must not replay an ambiguous
write automatically. Do not reset profiles to troubleshoot a network problem.

## Release verification

Acceptance requires real phones with home Wi-Fi disabled and an independently
configured VPN. Record source SHAs, installed app version/build, phone OS,
router firmware, VPN/client version, address type and results in the
[mobile device acceptance issue](https://github.com/owrtpc/mobile/issues/2).
Keep addresses, credentials, keys and QR codes out of public evidence.

| External connection | iOS physical device | Android physical device |
| --- | --- | --- |
| WireGuard | Pending | Pending |
| Tailscale alternative | Pending | Pending |

On 2026-09-09, the owner confirmed that connectivity worked on the Flint2 after
correcting the HTTPS rule from destination zone `lan` to router INPUT. The
active firewall was inspected after the correction. This confirms the fix for
that installation; the complete platform/build record and scenarios below
were not captured, so it does not close the full release matrix.

For each path verify login and fresh profile reads; read-only ACLs; one
deliberate reversible write with confirmed state; tunnel loss and reconnection;
an interrupted write with no automatic replay; and certificate mismatch
rejection. If using a hostname, also verify DNS. A browser reaching LuCI is a
useful network check, but it does not prove app authentication or API access.

Source inspection confirms the current Flutter transport uses normal HTTPS
sockets without Wi-Fi binding or a LAN-address allowlist. Endpoint and real TLS
tests verify application boundaries, not the operation of an external VPN.
The physical matrix remains pending until those scenarios are performed.
