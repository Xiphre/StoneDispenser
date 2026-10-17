# TradeStone

A small World of Warcraft addon for warlocks on WoW Forever (Classic-era client, interface 16001).

When the trade window is open it adds one button next to the Trade button, in the same style:

- **Trade Stone** (you carry a Healthstone): puts the best one from your bags into the first free trade slot.
  If the stone you carry is a lower rank than the best one you can create, the button shows Create & Trade instead and trades the new stone.
- **Create & Trade** (you don't): casts the best Create Healthstone spell you know, and when the new stone appears puts it into the trade. Casting needs a real click, so this is a secure button. If the trade closes before the cast finishes, nothing is traded.

Healthstones are picked best first: Major (9421), Greater (5510), Healthstone (5509), Lesser (5511), Minor (5512).

The addon does nothing on other classes.

## Install

Copy the `TradeStone` folder into the game's `Interface\AddOns` folder and enable it on the character screen.

## Key binding

Bind a key under Esc > Key Bindings > AddOns > TradeStone > "Create / Trade Healthstone". Pressing it does the same as clicking the button: when someone opens a trade with you, one press creates a Healthstone (if you have none) and puts it into the trade. The key does nothing when no trade window is open.

## Commands

- `/ts` or `/tradestone` prints what the addon found: create spells, spellbook entries, the chosen spell and the best stone in your bags.

## Notes

- The button can only switch between creating and trading out of combat. If your bags change in combat, it switches when combat ends.
- Spell IDs and names on Forever may differ from Classic. If the create button picks the wrong spell, run `/ts` and check the output.

See [CHANGELOG.md](CHANGELOG.md) for the version history.
