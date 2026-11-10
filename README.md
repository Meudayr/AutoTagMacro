# AutoTagMacro

World of Warcraft utility addon (compatible with WoW Forever `16001`, Classic `1.12`/`1.15`, Wrath `3.3.5`, and modern clients) that dynamically rewrites a dedicated `AutoTag` macro to target active quest mobs in your current zone and cast `Faerie Fire` (or a configured class tagging spell) without targeting corpses.

## Managed Macro Output

When active quest targets exist in your current zone:

```text
#showtooltip
/cleartarget [dead][noharm]
/targetexact [noexists] Young Nightsaber
/targetexact [noexists] Young Thistle Boar
/stopmacro [dead][noharm]
/cast [harm,nodead] Faerie Fire
```

When no quest targets are found for the current zone, `AutoTag` falls back to:

```text
#showtooltip
/cleartarget [dead][noharm]
/targetenemy [noexists]
/stopmacro [dead][noharm]
/cast [harm,nodead] Faerie Fire
```

## Slash Commands

Use `/autotag` or `/at`:

* `/at update` or `/at sync`: Force an immediate quest log rescan and macro update (queued if in combat).
* `/at status`: Display current zone, macro slot, character usage (`X/255`), and tracked quest targets.
* `/at debug`: Toggle verbose debug logging in chat.
* `/at spell <SpellName>`: Change the tagging spell (defaults to `Faerie Fire`).
