# Playing online with a friend

There is no shared server to set up. The person who **hosts** a room runs it on their own
computer, and the game makes an **invite link** for it. Whoever opens the link is taken into the
room.

## The host

1. **Play > Host Room.** Pick a name for the room, a password if you want one, and the game mode.
2. You land in the room screen. After a moment an **Invite link** appears there. Press
   **Copy link** and send it to your friend.
3. Stay in the room. The room, and its link, close when you leave it or close the game.

### Making the link work from anywhere

The game comes with a tunnel program, `cloudflared` (Cloudflare's, in `bin/cloudflared.exe`, with
its license next to it). When you host, the game starts it by itself and the link works from
anywhere, with no router or firewall settings and no account. Nothing has to be installed.

If the tunnel does not work, the game asks your router to open a port instead. Many routers allow
it; some do not, and some internet providers make it impossible. If neither works, the link still
works for people **on the same network as you**, and the note under the link says so.

To update the tunnel program, replace `bin/cloudflared.exe` with a newer
`cloudflared-windows-amd64.exe` from <https://github.com/cloudflare/cloudflared/releases>.

## The friend

1. Start the game once and pick a name (no email). When asked whether invite links may open the
   game, answer **Yes, allow**. (Settings > Online has a switch for it too.)
2. Click the link. A web page opens and hands it to the game: the game starts, goes to Play and
   joins the room. If the game is already open, that game comes to the front and joins instead
   (if you are in a room just then, it joins once you are back on Play). If the room has a
   password, it asks for it.

## How the link opens the game

Many chat apps only let you click web addresses, so the link is one:
`https://edoardonegri.github.io/Chronos/join.html#<room details>`. That page (`web/join.html`)
opens the game with a `chronos://` link, which Windows passes to the game once invite links are
switched on. The page has no server part and never sees the room details, which stay in the part
of the address after `#`.

The page is published by `.github/workflows/pages.yml` whenever `web/` changes on `main`. It needs
GitHub Pages switched on once: repository **Settings > Pages > Build and deployment > Source:
GitHub Actions**. Its address is `PAGE_URL` in `scripts/net/invite_link.gd`.

A game already open listens on port 47613 on this computer only (`scripts/net/invite_inbox.gd`);
a game started by a link passes the link to it there and closes.

## If something goes wrong

- *"Could not reach ..."*: the host closed the room or the game, or the link only works on the
  host's network and you are somewhere else (see "Making the link work from anywhere").
- *"That room is closed."*: the host left the room.
- *Nothing happens when you click a link*: invite links are not switched on for this computer.
  Turn them on in Settings > Online. (The question about it is only asked in an exported game,
  not when running from the Godot editor.)
- *The page says "404"*: GitHub Pages is not switched on yet, or the workflow has not run (see
  "How the link opens the game").

## A shared list of rooms (optional)

Settings > Online > Shared server lists open rooms from a server, so a room can be joined with a
click instead of a link. The server is `scripts/dev/server.ps1`; it is only needed if you want that.

## Running the game for your friend

Either they open the project in Godot 4.7.2 and press F5, or you export a Windows build: install
the export templates once (Editor > Manage Export Templates), then Project > Export > **Windows
Desktop** > Export Project. The preset (`export_presets.cfg`) is already set up: the build is one
`build/Chronos.exe` that carries the card files and the tunnel program, which the game unpacks into
its own data folder the first time someone hosts.
