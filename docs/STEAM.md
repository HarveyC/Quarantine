# Steam

Carriers runs with or without Steam. Without it (CI, the GitHub zips, `-- --no-steam`) online play
is ENet by address as before. With the GodotSteam GDExtension installed and Steam running, the
title screen offers **Host on Steam**, and online play goes through Steam lobbies and Steam's
relay: no port forwarding, no IP addresses.

## What Harvey needs to do

Development works today on Valve's test app id **480** (Spacewar). To ship on Steam:

1. **Steamworks account.** Sign up at https://partner.steamgames.com, accept the distribution
   agreement, and fill in the tax and bank forms (identity checks can take a few days).
2. **Pay the Steam Direct fee**, US$100 per game (recouped after US$1,000 in sales). This creates
   the app and gives you its **App ID**.
3. **Put the App ID in the game**: change `carriers/steam/app_id` in `project.godot` from 480.
4. **Install GodotSteam** in the project: Godot editor → AssetLib → "GodotSteam GDExtension"
   (the build for Godot 4.4, version 4.14 or newer; it includes SteamMultiplayerPeer) → install
   into `addons/godotsteam`, then commit that folder so exports include it.
5. **In Steamworks, set up:**
   - *Achievements*: one per id in `Achievements.DEFS`, API name = the id in upper case
     (`first_win` → `FIRST_WIN`).
   - *Stats*: INT stats named like `Achievements.stats()` keys in upper case (`RUNS`, `WINS`,
     `FIGHTS_WON`, `BOSSES_KILLED`, `NESTS_CLEARED`, `SOLDIERS_TURNED`, `FIELD_DATA_EARNED`,
     `HIGHEST_SEVERITY`).
   - *Rich presence*: upload `steam/rich_presence.vdf` (Community → Rich Presence).
   - *Steam Cloud*: turn it on with a byte quota (1 MB and 10 files is plenty). The game writes
     `profile.cfg` and `run_save.txt` itself, so Auto-Cloud isn't needed.
   - *Launch options*: point them at the Windows/Linux exports. Mark Steam Deck as "Unknown" until
     it has been tested.
6. **Store page**: capsule art, screenshots, a trailer, description. Steam requires the page to be
   public "Coming soon" for at least two weeks before release.
7. **Trademark check** on "Carriers" before the store page goes public.

## How it fits together

| File | What it does |
|---|---|
| `net/transport.gd` `NetTransport` | What NetSession talks to: makes a MultiplayerPeer, hosts/joins, reconnect copy |
| `net/enet_transport.gd` | Direct address (LAN, forwarded port, Tailscale, the CI playtests) |
| `net/steam_transport.gd` | Friends-only lobby tagged `game=carriers`, SteamMultiplayerPeer over the relay |
| `platform/platform.gd` (autoload `Platform`) | Starts Steam, runs callbacks, invites and join requests, rich presence, achievements and stats, cloud |
| `platform/cloud_sync.gd` | Steam Cloud mirror of the save files, newer copy wins on startup |
| `platform/crash_reporter.gd` | Spots an unclean exit, saves `user://crash_reports/crash-*.txt` with the log tail |

Steam is reached with `Engine.get_singleton("Steam")` and dynamic calls, so nothing fails to parse
when GodotSteam isn't installed. Tests run the whole Steam layer against `tests/fake_steam.gd`.

**Joining.** A friend joins from an invite (overlay), from "Join game" on the host in their
friends list (rich presence `connect` = `+connect_lobby <id>`), or Steam launches the game with
`+connect_lobby <id>` when it wasn't running. All three end in `App._join_steam`.

**Reconnects** work the same on both transports. A client that loses the host mid-match keeps its
state and retries for about 20 seconds (`NetSession.RECONNECT_DELAYS`); the host holds its slot
as absent (soldiers hunker, run benches it) and gives it back to the same client id, which is the
Steam id on Steam. A host that leaves on purpose sends a goodbye so clients don't wait.
`tests/net_playtest.sh` scenario 4 cuts a client off mid-match and checks it comes back in sync.

**Crash reports** stay on the player's PC unless `carriers/crash_reports/url` is set, then each
report is POSTed there as plain text. For full native crash dumps later, the Sentry Godot SDK is
the usual choice.

## Testing on Steam before you have an App ID

Run two copies on two PCs signed in to two Steam accounts that are friends, both with Steam open.
App id 480 shows the game as "Spacewar" in Steam; that's expected. Host on Steam on one, invite the
other from the overlay (Shift+Tab) or the friends list.
