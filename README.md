# ｋｉｎｏｐｌｅｘ

Kinoplex is a project for syncing media playback, aiming to be a simpler
replacement for Syncplay without all the bloat, and without relying on Python.

The project is comprised of a procotol, server, mpv client, and web client.
Clients targeted at other media players can easily be implemented thanks to the
simple JSON protocol. There are no official servers or support for rooms, since
the intended use case is syncing playback of videos and music for friend groups
using a single shared server. The server hosts a web client, and the mpv client
can be configured to connect to the server using a config file.


For user roles there can be only 1 admin that controls playback, acting as the
anchor point for syncing time and state. The admin can let other users be
jannies through a command, which gives them access to add URLs to the playlist.

## Installation

Compile using Nim 1.4.8 or higher (preferably 1.6.4).

Build the server (kino_server) and mpv client (kino_mpv):
```bash
nimble build -d:danger
```

Build the web client JavaScript:
```bash
nimble webclient
```

To run the mpv client, make sure you have mpv installed on your system. If
you're on Windows or using a custom build, make sure to change `binPath` in the
config file to point to the binary.

### Config

Copy `server.example.conf` to `server.conf` and/or `mpv_client.example.conf` to
`mpv_client.conf`, ideally in `~/.config/kinoplex` and modify them to your
needs. Allowed locations are next to the executable and in
`~/.config/kinoplex/`. The web client doesn't have a config.


## mpv

mpv's native playlist functionality is used to synchronize the playlist across
clients. The admin can go back and forth in the playlist without any issues,
other clients will follow it perfectly. As non-admin pausing and skipping ahead
doesn't work, the client constantly syncs time and state to be as close the
admin as possible. Chat and server messages are displayed using mpv's built-in
OSD overlay. If they aren't shown, you may have to change your mpv
configuration.

### Keybindings

| | |
| - | - |
| <kbd>Enter</kbd> | Open chat input, <kbd>Enter</kbd> again to send and/or exit |
| <kbd>/</kbd> | Open chat input with "/" already in the input (convenient for commands) |
| <kbd>Ctrl</kbd> + <kbd>l</kbd> | Clear chat |
| <kbd>Ctrl</kbd> + <kbd>q</kbd> | Fully quit mpv. Normal <kbd>q</kbd> will restart mpv. |
| <kbd>Ctrl</kbd> + <kbd>v</kbd> | Add clipboard to playlist (must be admin or janny) |

### Commands

Prefix for all commands is `/`. Press <kbd>/</kbd> to open the chat ready to
type a command.The shorthand notation `[c]md` means `/c` is the same as `/cmd`

| | |
| - | - |
| `[u]sers` | Show list of users in the server |
| `[l]og n` | Show `n` lines of the chat log. If `n` is empty, it shows 6 lines |
| `[a]dd url` | Add URL to playlist (admin and janny). <kbd>Ctrl</kbd> + <kbd>v</kbd> does the same. |
| `[i]ndex n` | Sets playlist index to `n` (number) (admin only) |
| `[j]anny u` | Grant janny role to user with username `u` (admin only) |
| `[o]pen path` | Replace current file or URL locally. Useful if you have a local copy of something being streamed |
| `[c]lear` | Clear chat, same as <kbd>Ctrl</kbd> + <kbd>l</kbd> |
| `[r]eload` | Reload playlist and state. Useful if mpv gets messed up |
| `restart` | If `reload` isn't enough to fix mpv, try this. Hitting <kbd>q</kbd> should do the same |
| `quit` | Same as <kbd>Ctrl</kbd> + <kbd>q</kbd>, fully quit mpv |

## Web

The web client can be accessed at the server's main path, e.g.
http://localhost:9001/ or https://kinoplex.example.com/

You're prompted to pick a username, and optionally your password if you're
admin. The web client has a chat overlay almost identical to mpv's, visible in
fullscreen-mode. Press <kbd>Enter</kbd> to show it, and again to send/close.

We use [plyr](https://github.com/sampotts/plyr) for playback which supports
YouTube and Vimeo links, as well as video and audio file links. For broadest
link support, consider using the mpv client instead since it uses youtube-dl to
stream from almost any source. mkv files are generally not supported by
browsers, but you can turn it into an m3u8 stream with ffmpeg easily which all
browsers support using hls.
