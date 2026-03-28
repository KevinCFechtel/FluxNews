# Flux News

<img src="assets/Flux_News_Starticon_Blue_Mac.png" width="150">

A Newsreader for the miniflux backend (<https://miniflux.app>).

This Newsreader sync with the miniflux server api.

Enjoy full offline support, intuitive swipe gestures, a true OLED black mode and open articles preferred in an already installed app.
<br/><br/>

## Download


[<img alt="Get it on F-Droid" height="100" src="./screenshots/fdroid.png">](https://f-droid.org/packages/de.circle_dev.flux_news/)

[<img alt="Get it on Google Play" height="100" src="./screenshots/googleplay.png">](https://play.google.com/store/apps/details?id=de.circle_dev.flux_news)

## Getting Started

Flux News requires Miniflux version >= [2.0.29](https://miniflux.app/releases/2.0.29.html).

1. In Miniflux, create an API key in Settings / API Keys.
2. Open the app, go to the Settings page
3. Add the server URL and the key (do **include** the `/v1/` part of the URL endpoint)
4. Save, go back and refresh!

The unread articles should appear in the app.

## Screenshots
### Phone
<p float="left">
<img src="screenshots/AllNewsLight.png" width="300">
<img src="screenshots/AllNewsDark.png" width="300">
<img src="screenshots/DrawerWithFeeds.png" width="300">
<img src="screenshots/NavBarMenu.png" width="300">
<img src="screenshots/Search.png" width="300">
<img src="screenshots/Settings.png" width="300">
</p>

### Tablet
<p float="left">
<img src="screenshots/Tablet_Light.png" width="600">
<img src="screenshots/Tablet_Dark.png" width="600">
<img src="screenshots/Tablet_Portrait.png" width="600">
</p>
<br/><br/>

## Features

Flux News is still in development but implements some common features for an RSS reader. Keep in
mind that this is a personal project which is moving forward depending on my free time. At the
moment, the following is supported:

**Intuitive Gesture Control:** Navigate your news with natural swipe gestures. Quickly triage your articles, mark them as read, or save them for later.

**Open articles in an app:** Articles can be opened in an already installed app.

**Mark as read on scrollover:** Articles are marked as read when you scroll over them.

**OLED-Optimized Design:** Choose between Light, Dark, and a specialized true black mode for OLED screens to save battery and reduce eye strain.

**Precision Filtering & Search:** Instantly sort through your content by status (Unread, Read, Starred), category, or individual feeds. Use the powerful search to query your entire Miniflux backend.

**Send an article:** Articles can be send to third-party services if enabled.

**Truncate an article:** Articles can be truncated to have a teaser instead of the full article text.

**Quick Access to Discussions:** Open article comments directly in the app to stay engaged with the community without leaving your newsreader.
<br/><br/>

## Limitations:

- No user management.
- No feed or category management.

## Permissions

* Internet permission is required to sync with the miniflux backend.
<br/><br/>

## Disclaimer

This program is free software: you can redistribute it and/or modify it under the terms of the Modified BSD License.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the Modified BSD License for more details.
