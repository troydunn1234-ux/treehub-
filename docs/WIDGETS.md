# Turning the widgets and Watch complications on

The widget code is in `StillPointWidgets/`, `PulseLabWidgets/`, `ClankerrWidgets/`, `FoodBookWidgets/`
and the targets exist in `project.yml`, but they are not embedded yet because the App Groups
(the shared container a widget reads from) must be created once in the Apple Developer portal,
which the CI's API key cannot do.

## One-time setup (developer.apple.com → Certificates, Identifiers & Profiles)

1. Identifiers → filter **App Groups** → **+** → create each of:
   - `group.com.troydunn.stillpoint`
   - `group.com.troydunn.pulselab`
   - `group.com.troydunn.clicker`
   - `group.com.troydunn.foodbook`
2. Identifiers → **App IDs** → open each ID below → tick **App Groups** → Configure → select its group → Save:
   - Still Point: `com.troydunn.stillpoint`, `com.troydunn.stillpoint.watchkitapp`,
     `com.troydunn.stillpoint.widgets`, `com.troydunn.stillpoint.watchkitapp.widgets`
   - Pulse Lab: `com.troydunn.pulselab`, `com.troydunn.pulselab.widgets`
   - Couch Remote: `com.troydunn.clicker`, `com.troydunn.clicker.watchkitapp`, `com.troydunn.clicker.watchkitapp.widgets`
   - Food Book: `com.troydunn.foodbook`, `com.troydunn.foodbook.widgets`
   (If a widget ID isn't listed yet, register it: App IDs → + → App → the identifier above.)
3. In `project.yml`, uncomment every line marked `TODO re-enable once App Groups are registered`,
   push, and run TestFlight for the four apps.
