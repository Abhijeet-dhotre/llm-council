# LLM Council — Flutter Android app

Five advisors argue it out, one chairman gives a verdict you can act on.
Local-only, no server, no account, no ads. Groq free tier, one model,
five personas.

## What is inside

- **Chat UI** — Apple / iMessage style. Blue bubbles for you, grey bubbles
  for advisors, the verdict arrives as a Chairman message with a GO / NO-GO /
  TEST FIRST badge, confidence, first step, biggest risk, and the strongest
  objection kept even when the chairman disagrees.
- **Council flow** — Groq first asks you 0–5 clarifying questions (it decides
  how many; every question is skippable), then Stage 1: five independent
  opinions, Stage 2: anonymous peer review, Stage 3: chairman's verdict in a
  fixed format (never free text).
- **Mascots** — Bloub blobs (MIT, by Jérémy Perret), one colour per advisor,
  animated by what the advisor is doing (thinking, speaking, happy bounce
  when it agrees, unimpressed when it loses the peer review).
- **Live facts (optional)** — with a Tavily key, the app fetches fresh
  sources before the council runs and shows them. Without it the council
  judges from the model's own knowledge and the verdict says so.
- **History** — every run is saved on-device (SQLite). Settings holds your
  keys in secure storage — nothing is ever hardcoded.

## Build it (Windows, PowerShell)

Prerequisites: Flutter SDK 3.50 or newer, Android Studio with the Android
SDK, JDK 17 (Android Studio bundles one — if `flutter doctor` complains
about Java, set `JAVA_HOME` to Android Studio's `jbr` folder, e.g.
`C:\Program Files\Android\Android Studio\jbr`).

```powershell
cd llm-council-mobile
flutter doctor
flutter pub get
flutter analyze
flutter build apk --debug
```

The APK lands at:

```
build\app\outputs\flutter-apk\app-debug.apk
```

For a release build instead (installable the same way, smaller and faster):

```powershell
flutter build apk --release
# build\app\outputs\flutter-apk\app-release.apk
```

Install it on your phone with USB debugging on:

```powershell
adb install build\app\outputs\flutter-apk\app-debug.apk
```

or copy the APK to the phone and tap it to install.

## Build it online (no Android Studio at all)

- **FlutLab** (https://flutlab.io) — fastest. Browser IDE, builds in the
  cloud, download the APK straight from the site. Free tier: 2 projects,
  250 MB, shared build queue. Import the project from a public GitHub repo
  (private repos need a paid plan).
- **GitHub Actions** — free for public repos (2,000 minutes/month).
  Push this project to a public repo; the workflow in
  `.github/workflows/build-apk.yml` builds the APK on every push to main
  and on manual runs. Download it from the run's Artifacts as `app-debug`.
- **Codemagic** (https://codemagic.io) — 500 free macOS build minutes/month,
  no card. Also needs the code in a GitHub / GitLab / Bitbucket repo; it
  detects the Flutter project and builds with almost no setup.

## First run

1. Open the app → Settings (gear icon, top right).
2. Paste your **Groq API key** (get one free at https://console.groq.com)
   and tap **Save key**, then **Test Groq** — it should answer OK.
   Default model is `openai/gpt-oss-120b` — check in the Groq console
   that it is still on the free tier; Groq moves models between tiers.
3. Optional: paste a **Tavily key** (1,000 free credits/month, no card, at
   https://tavily.com) for live facts.
4. Ask the council anything.

## Project notes

- Package: `com.muse.llm_council`, app name: LLM Council, version 1.0.0+1.
- Fonts: Fraunces (titles) + Plus Jakarta Sans (body), loaded via
  `google_fonts` — the phone needs internet on first run to fetch them.
- Mascot note: Bloub is an SVG recreation of the x.ai / Grok bot avatar.
  The code is MIT-licensed, but the design resembles x.ai's — check before
  publishing the app commercially.
- `flutter analyze` is clean; the widget smoke test in `test/` passes.
  A live Groq run has not been tested yet — the first question you ask on
  the phone is the first live run.
