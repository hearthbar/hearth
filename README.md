# Hearth

A Mac menu bar app for my Nest thermostat. Current temperature sits in the menu bar. Click it to get a dial and full control.

It talks to Google's official Smart Device Management (SDM) API. No scraping, no unofficial login.

## Layout

- `mac/`: the app. Swift package, build and release scripts, Info.plist, entitlements and icon.
- `docs/`: the website, the setup guide and the privacy policy, served at
  <https://hearthbar.app> by GitHub Pages.

Support and bug reports: [support@hearthbar.app](mailto:support@hearthbar.app).

## Features

- Current temperature in the menu bar
- Dial you can drag, scroll, or nudge with + and -
- Heat, Cool, Auto (Heat-Cool), and Off modes
- Separate heat and cool setpoints in Auto mode
- Eco mode on and off
- Fan timer
- Indoor humidity
- HVAC status: heating, cooling, or idle
- Multiple thermostats
- Auto-refresh every minute
- Open at login

Requires macOS 15 or later.

## Sign in

Open Hearth and click **Sign in with Google**. The browser opens. Pick your account, then your home and thermostat on Google's screen. Hearth lists what it found and you're done.

Hearth signs in through a Google project that ships inside the app. See [Built-in credentials](#built-in-credentials).

## Your own Google project (optional)

Only needed if you build without the built-in credentials, or want your own. Google makes you register as a developer for this. It takes about 15 minutes and costs a one-time $5. The same steps are at https://hearthbar.app/setup.html.

1. **Register for Device Access.** Go to https://console.nest.google.com/device-access, sign in with the Google account that owns the thermostat, accept the terms, and pay the $5 fee.
2. **Create a Google Cloud project.** Go to https://console.cloud.google.com and create a new project.
3. **Enable the API.** In that project, open APIs & Services > Library, search for "Smart Device Management API", and enable it.
4. **Set up the OAuth consent screen.** APIs & Services > OAuth consent screen. Pick **External**. Fill in the app name and your email. Under Test users, add your own Google account.
5. **Create an OAuth client.** APIs & Services > Credentials > Create credentials > OAuth client ID. Application type: **Desktop app**. Save the **Client ID** and **Client Secret**.
6. **Create a Device Access project.** Back in https://console.nest.google.com/device-access, create a project. Paste the OAuth Client ID from step 5 when asked. Skip Pub/Sub events. Copy the **Project ID** it shows you.
7. **Enter them in Hearth.** In the sign-in window, click **Use your own Google project**. Paste each value, or drop the client JSON file from Google Cloud on the window. Then sign in.

### Avoid signing in every week

While the consent screen is in "Testing" status, Google expires refresh tokens after 7 days. To stop that, go to OAuth consent screen and click **Publish app** to move it to "In production". It will say the app is unverified. That is fine for personal use. You just click through the warning once when you sign in.

## Build and run

```sh
mac/scripts/build-app.sh --install --run
```

This builds a universal binary (Apple silicon and Intel), packages a sandboxed `Hearth.app`, signs it, copies it to `~/Applications`, and launches it.

Signing picks the first identity it finds: `$SIGN_IDENTITY`, then Developer ID Application, then Apple Development, then ad hoc. Use a real identity when you can. Ad hoc signatures change every build, so Keychain asks for access again after each update.

The version comes from `VERSION`. The build number is the git commit count.

Other options:

- `mac/scripts/build-app.sh` builds `mac/build/Hearth.app` only
- `swift mac/scripts/make-icon.swift` regenerates the app icon
- `HEARTH_DEMO=1 mac/build/Hearth.app/Contents/MacOS/Hearth` runs with sample thermostats, no Google account needed

Coming from the first ad hoc build: the sandboxed app keeps its own settings and Keychain access, so you enter your credentials and sign in once more.

## Release

```sh
mac/scripts/release.sh
```

This builds the app and makes `mac/build/Hearth-<version>.dmg` with an Applications shortcut. The first run may ask to let Terminal control Finder. That only styles the DMG window. Saying no is fine.

### Signing and notarization

A DMG signed with Apple Development works on this Mac only. Other Macs block it until it is signed with Developer ID and notarized. One-time setup:

1. Join the Apple Developer Program.
2. Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application.
3. Store notary credentials:

   ```sh
   xcrun notarytool store-credentials hearth --apple-id <email> --team-id M64T9MW7V8
   ```

After that, `release.sh` signs with Developer ID, notarizes, and staples the DMG on its own. Set `NOTARY_PROFILE` to use a different profile name.

### Built-in credentials

`mac/Resources/HearthCredentials.plist` holds the Project ID, Client ID and Client Secret of the Google project Hearth signs in through. Keys: `ProjectID`, `ClientID`, `ClientSecret`. It is gitignored. `build-app.sh` copies it into the app bundle, and debug builds read it from the source tree. Without it, Hearth opens straight to the own-project form.

Limits to know about:

- A Device Access sandbox account allows 25 users across 5 homes, shared by all its projects. See https://developers.google.com/nest/device-access/project/limits.
- Other Google accounts must be test users on the OAuth consent screen, or the app must be published.
- A published app that Google hasn't verified shows an "unverified app" warning at sign-in. Verification needs the homepage and privacy policy at https://hearthbar.app.
- Each person picks their own home and thermostat on Google's screen.

## Troubleshooting

- **No thermostats show up.** The thermostat wasn't turned on in Google's permissions screen. Click **Choose Thermostats**, or **Change Thermostat Access** in Account and Settings, and turn it on.
- **"Access blocked" or "app not verified".** Make sure your account is listed as a test user, or that the app is published. Click Advanced > Go to app to continue past the unverified warning.
- **Sign-in worked a week ago and now fails.** The consent screen is still in Testing. Publish it (see above) and sign in again.
- **"Invalid client" or redirect errors.** The OAuth client must be type Desktop app. Web clients will not work with the local sign-in redirect.
- **Commands fail with a 400 error.** Some settings only apply in certain modes. For example, you cannot set a cool setpoint while in Heat mode, and setpoints are locked while Eco is on.
- **macOS says the app can't be opened.** Right-click Hearth.app in `~/Applications` and choose Open.
