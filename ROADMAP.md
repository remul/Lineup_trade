# Roadmap

Planned features, ideas and open questions for Lineup Trade. Move an entry to
[CHANGELOG.md](CHANGELOG.md) when it ships, and delete it here.

## Next

- **Shared record (optional):** if participants can be in a custom chat channel, results could be
  reported over addon messages (the server adds the sender's character, so IDs are tied to
  characters). That would close the "first meeting" gap below.
- **Leaderboard** for the organiser, from the shared record.

## To check in game

- Pet names accept the code (letters only, 12 characters) and the opponent sees it in PvP.
- `C_PetJournal.SetCustomName` and `SetPetLoadOutInfo` work from the Start button and the team
  choice.
- The trade key: `StartPVPMatchmaking`, `AcceptQueuedPVPMatch` and `ForfeitGame` work from a key
  binding, and a forfeit counts as a win for the opponent.
- Both sides count each trade game once: `PET_BATTLE_FINAL_ROUND` after a normal end, and the
  forfeit fallback in `Battle.lua` when a forfeit ends the battle without it.

## Known limits

- The first time two players meet, there's nothing to compare their code with: a copied or reset
  code is only caught by players who have seen that ID with a higher game count before.
- The balance in the code only goes from -12 to +13, and the game count up to 675; restoring a
  record from the pet name assumes the real values are within that.
