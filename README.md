# Premium for iPhone

A personal, open-source, ad-free YouTube client for iOS — the iPhone version of the Premium Android app — in the **Pearl Glass** style (light frosted glass, rainbow focus edges), with Classic, Daylight and Midnight Glass as alternative themes.

## What's in it
- **Home** — greeting, Continue watching / Up next / watch-time / Cast widgets, category chips, a mixed feed from your subscriptions and what you watch
- **Search** — suggestions as you type, recent searches, voice search, filters (date, length, Live, Shorts)
- **Watch page** — HD playback, chapters, SponsorBlock auto-skip, comments, queue, speed, audio-only mode, sleep timer, Picture in Picture, background audio, lock-screen controls
- **Shorts** — full-screen vertical swipe feed (For you / Subscriptions)
- **Subscriptions** — new uploads from the channels you follow (stored on the phone)
- **You** — watch time, history, Watch later, liked videos, playlists, queue
- **Channel pages** — Videos / Shorts / Live
- **Cast to Roku** — finds your Roku on Wi-Fi, plays the video in the TV's YouTube app, full remote
- **Settings** — 4 themes, evening mode, ambient glow, SponsorBlock categories, blocked words, backup & restore

## How it's built (no Mac needed)
Every push to `main` runs **GitHub Actions** on a cloud Mac:
1. `xcodegen` turns `project.yml` into an Xcode project
2. builds `Premium-simulator.zip` — upload this to **appetize.io** to run it in the browser
3. builds `Premium-unsigned.ipa` — sideload with AltStore / Sideloadly to run it on a real iPhone

Download both from the run's **Artifacts** on the Actions tab. If you add an `APPETIZE_TOKEN` secret (and optionally `APPETIZE_APP`), the workflow uploads to Appetize for you.

Streams come from [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit); search, feeds, channels and comments come from YouTube's web API. Personal use only.
