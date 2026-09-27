# Neo Nursery v1.0.0

Neo Nursery is officially at **1.0**.

This mod turns Pokémon Crystal's Johto Day Care into a full Tamagotchi-style Baby Pokémon system. Meet Zelda, receive the Baby Monitor, choose an Egg, and raise your baby through feeding, play, cleaning, sleep, illness, Friendship, and eventually adoption into your real party.

## What is in 1.0?

Neo Nursery supports **19 babies** in total: Crystal's eight official Baby Pokémon plus **11 reconstructed cut babies** that are gradually unlocked through Nursery progression.

Babies have persistent FOOD, FUN, CLEAN, Friendship, age, weight, sleep schedules, preferences, digestion, waste, sickness risk, COND, thought-bubble reactions, and their own independent real-time care clocks. The Nursery supports three residents at once, offscreen hatching, PAUSE CARE, Zelda calls, and a real Key Item Baby Monitor that can be registered to SELECT.

PLAY includes three minigames:

- **BOUNCE** — a 10-round Poké Ball timing game.
- **MATCH** — react to the baby's raised flags.
- **MEMORY** — repeat increasingly long D-pad sequences.

At 100 Friendship, Nursery-born babies can be adopted into the party or PC. Friendship synchronizes with Crystal's hidden happiness system, so happiness evolutions work naturally after adoption. The first full-Friendship milestone also earns an Everstone for anyone who wants to keep a baby unevolved.

## Reconstructed babies

The eleven unlockable Neo babies are:

**Mikon, Monja, Gyopin, Para, Hinazu, Konya, Puchikon, Betobebi, Pudi, Baririna, and Tsuinzu.**

Each is Nursery-exclusive and evolves through happiness into its associated Crystal family. Reaching full Friendship with a species for the first time unlocks one random undiscovered Neo Egg, with no duplicate unlocks.

## CRYSTAL / NEO presentation

Official babies begin with their released Crystal presentation. Mastering that species at full Friendship unlocks an alternate **NEO** Sprite Style.

Neo Nursery reconstructs official Crystal presentation from the player's imported game data at runtime. The release does not bundle extracted official Pokémon sprite PNGs.

## Compatibility

A huge part of the final QA pass went into cross-mod behavior.

**PokeSurvive:** For full cut-baby randomizer compatibility, use **PokeSurvive 2.1.4 or newer**. RAND TYPES, RAND STATS, and RAND MOVES all recognize the reconstructed babies while still keeping them out of normal wild/Trainer/rental species pools. Randomized typings, palettes, stats, and moves remain coherent through hatching, save/reload, adoption, Summary, battle, re-dropoff, and evolution.

**Mutant Monster Lab:** per-Pokémon palette mutations persist through Nursery transfers and Sprite Style changes.

## Care timing

Neo Nursery uses real elapsed time for baby care. Eggs use the compatible Crystal/PokeSurvive clock for incubation. PAUSE CARE freezes Nursery care when needed.

Remember that normal Pokémon SAVE behavior still matters: actions performed after your most recent save can roll back if you quit without saving.

## Installation

Use **gen1recomp 0.3.8 or newer** with a legally obtained Pokémon Crystal (USA/Europe Rev 1) ROM. Install the Neo Nursery release ZIP through the launcher, enable it for Crystal, and visit Zelda in the Johto Day Care.

Repository: https://github.com/GawdMode/Neo-Nursery

Thank you to everyone who helped test this thing while it was being hammered on. 1.0 is the point where the core Nursery experience is complete and ready to play. Bugs and strange mod interactions may still turn up, and those can be handled in follow-up releases.
