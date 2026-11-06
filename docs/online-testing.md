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

The game tries two things to get an address that someone far away can use:

- **A tunnel (best).** Put `cloudflared.exe` next to the game (or install it with
  `winget install Cloudflare.cloudflared`). The game starts it by itself and the link works from
  anywhere, with no router or firewall settings. Download it from
  <https://github.com/cloudflare/cloudflared/releases> (the `cloudflared-windows-amd64.exe` file,
  renamed to `cloudflared.exe`). Only the host needs it.
- **The router.** Without it, the game asks your router to open a port. Many routers allow it; some
  do not, and some internet providers make it impossible.

If neither works, the link still works for people **on the same network as you**, and the note
under the link says so.

## The friend

1. Start the game once and pick a name (no email). When asked whether invite links may open the
   game, answer **Yes, allow**. (Settings > Online has a switch for it too.)
2. Open the link. The game starts, goes to Play and joins the room. If the room has a password,
   it asks for it.
3. If your chat app does not let you click the link, copy it, open **Play** in the game, paste it in
   the box at the top and press **Join link**.

## Making links clickable in any chat app

Many chat apps only let you click web addresses. `web/join.html` is a single page that takes a
link and opens the game from it. To use it:

1. Publish `web/join.html` anywhere that serves static files for free (Cloudflare Pages, GitHub
   Pages, Netlify). It has no server part and never sees the room details, which stay in the part
   of the address after `#`.
2. Put its address in `PAGE_URL` in `scripts/net/invite_link.gd`.

From then on the **Copy link** button gives a web address, which any chat app lets you click.

## If something goes wrong

- *"Could not reach ..."*: the host closed the room or the game, or the link only works on the
  host's network and you are somewhere else (see "Making the link work from anywhere").
- *"That room is closed."*: the host left the room.
- *Nothing happens when you click a link*: invite links are not switched on for this computer.
  Turn them on in Settings > Online, or paste the link into the box in Play.

## A shared list of rooms (optional)

Settings > Online > Shared server lists open rooms from a server, so a room can be joined with a
click instead of a link. The server is `scripts/dev/server.ps1`; it is only needed if you want that.

## Running the game for your friend

Either they open the project in Godot 4.7.2 and press F5, or you export a Windows build
(Project > Export; install the export templates first from Editor > Manage Export Templates). Turn
on **Embed PCK** so the build is one `.exe`, and add `*.json` and `official_cards/*` to the filter
for non-resource files so the card files come along.
