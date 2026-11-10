# AutoTagMacro

**Note: While AutoTagMacro works completely standalone, functionality is greatly enhanced by having Questie installed. Questie allows the addon to resolve all item-drop quest mobs, check faction hostility, and prioritize targets by exact distance to your player coordinates.**

AutoTagMacro automatically scans your quest log and maintains an action bar macro and direct keybind that target incomplete quest mobs in your current zone.

When you enter an area, change zones, or progress a quest, the addon updates your target list so you don't have to manually write `/tar` macros while leveling.

---

### Key Features

*   **Zone-Aware Quest Targeting**: Identifies hostile mobs needed for active kill and item-collection quests in your current zone.
*   **Two Ways to Use**:
    *   **Action Bar Macro**: Creates an `AutoTag` macro that you can drag straight to any action bar slot.
    *   **Direct Keybind**: An optional keybind set in `/at` that cycles through all zone quest mobs without being limited by WoW's 255-character macro cap.
*   **Automated Combat Action**: Optionally casts a tagging spell (e.g. *Faerie Fire*, *Moonfire*, *Hunter's Mark*, *Shoot*) or starts auto-attacking immediately upon acquiring a target.
*   **Non-Toggling Raid Marker**: Places a selected raid icon (Star, Skull, etc.) on living quest targets and keeps it on while spamming.
*   **Gray-Tag Awareness**: Detects mobs already tagged by other players outside your party, avoiding wasted casts and skipping them out of combat.
*   **Corpse Re-Target Protection**: Avoids getting stuck repeatedly re-targeting dead corpses at your feet when distant living mobs are nearby.
*   **Temporary Mob Exclusions**: Right-click any targeted NPC frame (or click its name in `/at`) to temporarily exclude that mob from your target rotation. Exclusions reset automatically when you leave the zone.

---

### How to Use

1. Type `/at` to open the configuration menu.
2. Click **Pickup Action Bar Macro** and place it on your bars, or click **Bind Direct Key** to assign a dedicated key.
3. Configure your tagging spell, auto-attack preference, or raid marker as desired.

---

### Slash Commands

*   `/at` or `/autotag` – Open options menu
*   `/at sync` – Force an immediate quest rescan and macro update
*   `/at exclude` – Temporarily exclude your current target while in the zone
*   `/at exclude clear` – Restore all excluded mobs in the current zone
*   `/at status` – Display active zone targets and character budget in chat
