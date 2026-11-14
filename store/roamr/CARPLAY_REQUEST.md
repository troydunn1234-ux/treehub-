# Roamr: CarPlay entitlement request

Submit at https://developer.apple.com/contact/carplay (signed in with the developer account
that owns the app). Paste the answers below into the form.

---

**App name:** Roamr

**Bundle ID:** com.troydunn.roamr

**App Store status:** In development / TestFlight (iOS 17+)

**CarPlay app category:** Driving task

**Entitlement requested:** `com.apple.developer.carplay-driving-task`

**Describe your app and the CarPlay experience (what the driver sees and does):**

> Roamr is a trip recorder for drives, walks, runs, hikes and bike rides. For drives it records
> the route, speed, trip time and distance, and with "Go Together" a small group of friends
> driving to the same place can see each other's live position and speed.
>
> The CarPlay experience is a simple, glanceable driving-task dashboard built only from system
> templates (CPTabBarTemplate, CPInformationTemplate, CPListTemplate, CPAlertTemplate):
>
> 1. **Drive tab (information template):** current speed, trip time and trip distance, plus one
>    button: "Start drive" or "Stop drive". Stopping saves the trip to the phone.
> 2. **Go Together tab (list template):** the friends in the driver's current group trip, each
>    with their current speed and how far ahead or behind they are (for example
>    "52 mph · 0.4 mi ahead"). Rows are informational only.
>
> There is no text entry, no maps, no media, no video and no free-form content on the car
> screen. Everything else (setup, invites, history, settings) stays on the iPhone.

**Why is this a driving task?**

> Starting and stopping the trip recording and checking trip stats are tasks the driver
> performs while driving. Doing them on the CarPlay screen with one tap is safer than picking
> up the phone. The Go Together list lets a convoy check where the others are without touching
> the phone.

**Does the app use templates only?** Yes. No custom drawing on the CarPlay screen.

**Driver distraction:** One action button per screen, short static labels, information refreshes
about once a second. No notifications are shown on CarPlay beyond what iOS shows itself.

**Location / privacy:** Location is only used while a drive is being recorded. Go Together
positions are shared only with people who have that trip's code, and only until the trip ends.

**Test instructions for review:** Open Roamr on the iPhone, allow location, connect to CarPlay
(or the CarPlay Simulator in Xcode → I/O → External Displays → CarPlay). Tap "Start drive" on
the Drive tab, drive or simulate a route, then "Stop drive". To see the Go Together tab filled
in, start a Go Together trip on the phone and join from a second device.

---

## After Apple approves

1. In Certificates, Identifiers & Profiles → Identifiers → com.troydunn.roamr, the CarPlay
   capability appears; make sure it's enabled, then regenerate the provisioning profiles.
2. In `project.yml`, under the Roamr target's `entitlements.properties`, add
   `com.apple.developer.carplay-driving-task: true` and run `xcodegen generate`.
3. The scene configuration is already in Info.plist (`UIApplicationSceneManifest` →
   `CPTemplateApplicationSceneSessionRoleApplication` → `RoamrCarPlaySceneDelegate`), and the
   code is in `TrackApp/CarPlay/CarPlaySceneDelegate.swift`. Nothing else to wire up.
4. Test in Xcode's CarPlay Simulator, then ship a TestFlight build.
