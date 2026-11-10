# AdBlock for iOS

An iPhone ad blocker with two layers:

| Layer | Where it works | How |
|---|---|---|
| **Safari content blocker** | Web pages in Safari | `WKContentRuleList` rules compiled from the block list |
| **System DNS filter** | Every app that uses the system resolver (including the YouTube app, though see limits below) | `NEDNSProxyProvider` answers blocked domains with NXDOMAIN and forwards everything else |

Both layers read the same block list from an App Group container.

## Layout

```
project.yml                         XcodeGen spec (generates the .xcodeproj)
App/                                Container app (SwiftUI): status, toggles, list updates
Shared/BlocklistStore.swift         Domain list storage, hosts-file parsing, suffix matching
Shared/ContentRuleCompiler.swift    Domain list -> Safari content-blocker JSON
Shared/DNSMessage.swift             DNS packet parsing and NXDOMAIN reply building
SafariContentBlocker/               Safari content blocker extension (serves the rules)
DNSProxy/DNSProxyProvider.swift     System-wide DNS filter network extension
Tests/DNSTests.swift                Unit tests for parsing, matching and rule generation
```

## Build and run

Requirements: a Mac with Xcode 15 or later, an Apple Developer account, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

1. Replace `YOUR_TEAM_ID` in `project.yml` with your Team ID.
2. Replace `com.yourcompany` and `group.com.yourcompany.adblock` in `project.yml`, `Shared/BlocklistStore.swift` and `App/AppModel.swift` with your own identifiers. The three must agree:
   - App Group: `group.<you>.adblock` in all three entitlements files and `AppGroup.identifier`.
   - Extension bundle IDs: `AppModel.safariExtensionID` and `AppModel.dnsExtensionID`.
3. Run `xcodegen generate`, then open `AdBlock.xcodeproj`.
4. In the Apple Developer portal, create the App Group and enable the **Network Extensions** capability (DNS proxy) for both the app ID and the DNS extension ID. Apple may ask you to justify the Network Extension entitlement during review.
5. Build and run on a physical iPhone. The DNS filter cannot be tested in the Simulator.
6. On the phone: tap **Filter DNS for all apps** and approve the VPN-style prompt. Then go to Settings → Safari → Content Blockers and enable AdBlock.

Run the unit tests with Cmd-U. They cover DNS parsing, the NXDOMAIN reply, suffix matching and hosts-file parsing.

## What it can and cannot block

Be realistic about iOS limits before you promise anything in the App Store listing:

- **Safari:** blocks ad and tracker requests on web pages. Reliable, and Apple's supported approach.
- **Other apps via DNS:** blocks ad and tracker domains for apps that use the system resolver. Works well for many ad networks, analytics SDKs and in-app banners.
- **YouTube:** the YouTube app and youtube.com in Safari are only partly covered. Many YouTube ads are served from the same domains (`googlevideo.com`, `youtube.com`) as the video itself, and DNS cannot separate them. Expect ad-free behavior to be incomplete. Do not market YouTube ad blocking as a guaranteed feature.
- **Encrypted DNS and bypasses:** apps or browsers that use their own DNS-over-HTTPS, iCloud Private Relay, or a different VPN can bypass the DNS filter.
- **One DNS proxy at a time:** enabling this filter may conflict with another DNS or content filter app.
- **No ad removal inside content:** neither layer can hide ads that are part of a page or app's own layout.

## Privacy

The DNS extension sees every domain name the device resolves. The code does not log or store those names. Only the block list is stored locally in the App Group. Your App Store privacy label and privacy policy must say this truthfully. The list updates download a public hosts file over HTTPS. Confirm the license of any list you ship (for example, AdAway's hosts list) and credit it in the app.

## Known gaps before release

- Nothing here has been compiled or run. It was written without access to Xcode or an iOS device. Expect some fixes on the first build, most likely in the `NEDNSProxyProvider` code and the extension Info.plist keys (compare them with the templates Xcode generates for a Safari content blocker and a DNS proxy).
- The DNS proxy forwards to `1.1.1.1` with no fallback. A resolver setting that follows the user's network would be better.
- The DNS block list is read from disk and parsed inside the extension's flow handler, which is slow for very large lists. Pre-compile it into a trie or set if lists grow.
- No app icon, onboarding, or localization yet.
