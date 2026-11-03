# Project status (checkpoint)

**Updated:** 3 November 2026, 07:00 UTC. Branch `claude/friendly-turing-1hh9nu`.

## Done and tested (Lune, stand-in engine)
- Combat core and Fighting System v2, client feel: combat_test 40/40, smoke_combat 11/11.
- Matches, saving, receipts (with fakes), rewards and mastery: unit tests 117/117, data_test
  26/26, integration 12/12.
- Strong Dude, Ghost, Machine Master and Grandmaster: all power tests pass.
- Archive book and lore: lore_test 8/8, smoke_archive 10/10.
- 3 Nov: spectator predictions no longer pay anything (owner rule).

## In progress (batch 1, release blockers)
- Statues: finishing all eight with plinths.
- Hub: enclosed octagonal atrium, no grass, eight working doors, then Thanksgiving.
- Phase evolution during matches with Money fees (replaces the pre-match degree price). The
  lobby lock, free training trials and owner showcase mode are already written.
- Next in this batch: the interface and selection screens (half-rewritten when the previous
  agent hit the usage limit), and the shop with regional pricing and FINAL_OWNER_HANDOFF.md.

## Known defects
- smoke.luau: lobby, components and powers-window checks fail until the hub and interface
  work lands.
- Corruption 15/16, Shapeshifter 15/16 and Syntax 29/32 power tests failing; the Admin power
  test is unfinished and hangs.
- Market and Watch doors only show "opens soon".
- Nothing has been checked in a live Roblox server: physics, networking, DataStores, real
  purchases and multi-server behaviour need the owner's Studio and live tests.

## Usage notes
Each 5-hour usage window has supported roughly 30 minutes of four agents. Agents now get
narrow tasks and the cheaper Sonnet model; the lead session reviews and integrates.

## Next step
Integrate batch 1 as it lands (run the full suite, commit), then the interface agent and the
shop/pricing agent, then batch 2 starting with Jeffery and combat targeting.
