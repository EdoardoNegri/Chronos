# Playing online with a friend (testing)

There is no public server yet, so one of you runs the lobby server on their own PC and the other
reaches it through a free tunnel. Nobody has to change router settings.

## The person who runs the server

1. Start the server (leave this window open):

   ```powershell
   ./scripts/dev/server.ps1
   ```

   It prints `Lobby server listening on port 9080`. Use `-Port 9100` for another port.

2. Make it reachable from the internet. In a **second** window, install and run a Cloudflare quick
   tunnel (free, no account):

   ```powershell
   winget install Cloudflare.cloudflared
   cloudflared tunnel --url http://localhost:9080
   ```

   It prints an address like `https://quick-words-here.trycloudflare.com`. **That address changes
   every time you start the tunnel.** Send it to your friend.

3. In the game, you can leave Settings > Online > Server as it is (`ws://127.0.0.1:9080`, this PC).

## The friend

1. Start the game, open **Settings > Online > Server** and paste the address you were sent
   (`https://...trycloudflare.com`; the game turns it into a secure `wss://` address).
2. Open **Play**. The first time you are asked for a name: just a name, no email.
3. If the list says it could not reach the server, check the address and press **Refresh**.

## Playing

- One of you presses **Host Room** (a password is optional). It goes to the room screen.
- The other sees the room in the list and presses **Join** (a padlock on the left of Join means it
  needs a password).
- Both are now in the room screen. Use the chat to see that the connection works. **Leave room**
  goes back to the list; if the host leaves, the room closes.

## If something goes wrong

- *"Could not reach the server"*: the server window is closed, the tunnel is not running, or the
  address has a typo or is an old tunnel address.
- *"The server ... did not answer"*: the address is right but nothing answers there (wrong port).
- The server and the tunnel only work while the host's PC is on and both windows are open.
- Quick tunnels have no uptime promise: they are for testing, not for a public server.

## Running the game for your friend

Either they open the project in Godot 4.7.2 and press F5, or you export a Windows build
(Project > Export; install the export templates first from Editor > Manage Export Templates). When
exporting, add `*.json` and `official_cards/*` to the filter for non-resource files, so the card
files come along.
