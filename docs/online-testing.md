# Playing online

There is no server of our own. The person who **hosts** a room runs it on their own computer, and
the game puts the room in a **room list** that every copy of the game reads. Other players see it
in **Play** and press **Join**, which connects them straight to the host's game.

## Playing

1. **Play.** The first time, pick a name (no email).
2. **To host:** Host Room, pick a name, a password if you want one, and the game mode. You land in
   the room screen, which says when your room is in the list (it takes a few seconds). Stay in the
   room: it leaves the list when you leave it or close the game.
3. **To join:** the list fills in by itself (press **Refresh** to read it at once). Press **Join**
   on a room. If it has a password, the game asks for it.

## How it works

- **The room list is GitHub issues** in the game's own repository, `EdoardoNegri/Chronos`
  (`REPOSITORY` in `scripts/net/room_board.gd`). Each open issue titled `[Room] …` is one room;
  other issues are left alone. Its text holds the
  room's name, host, mode, whether it has a password, and the address to reach the host's game.
  The password itself is never in it: the host's game checks it.
- **Hosting** opens an issue once the host's game can be reached from the internet: the game tries
  its own tunnel address first, so a room is only listed once it works. While the room is open,
  the host's game says every 5 minutes that it is still there. **Leaving the room, or closing the
  game window,** closes the issue.
- **Joining** tries to reach the host 3 times, a couple of seconds apart, before giving up.
- **A room whose host is gone** is cleaned up two ways: the first player who cannot reach it
  closes it, and a room whose host has not said it is there for 20 minutes (their game crashed or
  the computer was switched off) is left out of the list and closed. If a host is in fact still
  there, its next heartbeat puts the room back.
- **The code:** `scripts/net/lobby.gd` (the connection, and the messages between the games),
  `lobby_host.gd` (the rules of a hosted room), `room_listing.gd` (keeping a hosted room in the
  list), `room_board.gd` (the list on GitHub) and `reachability.gd` (the tunnel).
- **Reaching the host from anywhere:** the game comes with a tunnel program, `cloudflared`
  (Cloudflare's, in `bin/cloudflared.exe`, with its license next to it). When you host, the game
  starts it by itself and gets a public address for your game, with no router or firewall
  settings and no account. If the tunnel does not work, the game asks your router to open a port.
  If that fails too, the room is listed as reachable **only from your own network**, the room
  screen says so, and players elsewhere who try it are told so (it is not taken off the list).

## Setting up the room list (once)

1. Make a token that can only touch the repository's issues: GitHub > Settings > Developer
   settings > **Fine-grained personal access tokens** > Generate new token.
   - Repository access: **Only select repositories** > `Chronos`.
   - Permissions > Repository permissions > **Issues: Read and write**. Nothing else (in
     particular not Contents: the token must never be able to change the code).
   - Pick an expiry; when it runs out, make a new one and rebuild the game.
2. Save the token in **`secrets/github_token.txt`** in the project folder (just the token, one
   line). `secrets/` is in `.gitignore`, so it never goes into the repository. GitHub turns off
   tokens it finds in public repositories, so never commit it.
3. Export the game (below). The token goes inside the `.exe`.

**About the token:** anyone with the game could dig it out of the `.exe`. That is why it may only
touch issues: the worst anyone can do with it is mess with the repository's issues, never the
game's code. If that ever happens, delete the token on GitHub and make a new one.

**The repository is public,** so anyone can see the room issues, including the address of each
open room's host. The address is a temporary tunnel that only works while the room is open, and
nothing else about the host is in it.

The token allows 5000 requests an hour, shared by everyone playing. Each open Play screen reads the
list every 30 seconds (120 an hour), so that is plenty for tests with friends.

## Running the game for others

Export a Windows build: Project > Export > **Windows Desktop** > Export Project (the export
templates must be installed once, from Editor > Manage Export Templates). The preset
(`export_presets.cfg`) is already set up: the build is one `build/Chronos.exe` that carries the card
files, the tunnel program and the token. The game unpacks the tunnel program into its own data
folder the first time someone hosts.

Windows warns about the `.exe` because it is not signed: **More info > Run anyway**.

To update the tunnel program, replace `bin/cloudflared.exe` with a newer
`cloudflared-windows-amd64.exe` from <https://github.com/cloudflare/cloudflared/releases>.

## If something goes wrong

- *"The room list is not set up"*: the game has no token. See "Setting up the room list".
- *"GitHub refused the game's token"*: the token expired or was deleted. Make a new one, put it in
  `secrets/github_token.txt` and export again.
- *"The repository … was not found"*: the token was not given access to `EdoardoNegri/Chronos`.
- *"Could not reach …"*: the host closed the game. The room is taken off the list.
