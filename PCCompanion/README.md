# Clankerr PC

Control your Windows PC from the Clankerr iPhone app: trackpad, keyboard, media and volume, open apps and games, lock or sleep.

## Set up (once)
1. Download **ClankerrPC.exe** from https://github.com/troydunn1234-ux/treehub-/releases/tag/pc-latest
2. Run it. If Windows SmartScreen warns you, click **More info → Run anyway** (the app isn't signed).
3. When Windows Firewall asks, allow it on **Private networks** (your home Wi-Fi). Leave Public unchecked.
4. On your iPhone, open Clankerr → **PC** tab. Your PC shows up; tap it.
5. A 6-digit code pops up on the PC. Type it on your phone. Done: the phone is remembered.

To start it with Windows: press Win+R, type `shell:startup`, and put a shortcut to ClankerrPC.exe in that folder.

## Privacy and safety
- Works only on your local network (private IP addresses). Nothing goes to the internet.
- A phone must enter the code shown on the PC before it can do anything. Paired phones are stored in `%APPDATA%\Clankerr\tokens.json`; delete that file to unpair all phones.
- The phone can only open apps from your Start Menu list, not arbitrary files.
