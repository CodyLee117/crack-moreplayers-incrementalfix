# More Players Incremental Fix

Companion BepInEx 5 plugin for **khovanet's More_Players** (crackmods.moreplayers) that lets
its upper-quarters annex build in **Incremental mode** (CRACK 2.0).

## The bug

More_Players raises the crew cap to 8 (configurable to 32) and gives players 5-8 rooms in an
annex above the quarters, reached by a ladder through a hatch in the lobby ceiling. All of its
player-cap patches are mode-agnostic and already work in Incremental:

- `MyNetworkManager.Awake` postfix → `maxConnections = MaxPlayers`
- `GameManager.GetAvailablePlayerIndex` prefix → index loop runs to `MaxPlayers` instead of 4
- lobby handshake (`cmods2`), door badges, bed sharing, spawn points

The annex does not. `QuartersAnnex.FindLadderSource` clones its hatch ladder from a scene root
named `PF_PushScaffold*`. In Incremental mode the game's `ModeSetup.Apply` (which runs on host
*and* every client at game-scene load) deletes every `PushableScaffold` as story-only content —
before the annex builds at `NetworkServer.SpawnObjects` / `NetworkClient.PrepareToSpawnSceneObjects`.
The clone throws, More_Players catches it and logs *"players 5+ will share rooms instead"*.

Net effect in Incremental without this fix: 8 players can join, but players 5-8 double up in
rooms 1-4 (roommate spawn offset, roommate's door badge, shared beds). No annex, no hatch.

## The fix

A Harmony prefix on `ModeSetup.Apply` snapshots the ladder subtree
(`FBX_Scaffolding_01/SM_Scaffolding_Ladder_01`) before Incremental cleanup destroys it, and
re-exposes it as an **inactive** root named `PF_PushScaffold` with the exact hierarchy
`FindLadderSource` searches for:

```
PF_PushScaffold (inactive, SnapshotMarker)
└── FBX_Scaffolding_01
    └── SM_Scaffolding_Ladder_01 (+ Ladder component, meshes, colliders)
```

- Story mode is untouched (the prefix early-returns).
- The snapshot is deterministic → host and clients produce the identical template → the
  annex builds the same everywhere, which is More_Players' own hard requirement.
- Final ladder scale is normalized by More_Players itself (`localScale = Vector3.one` under a
  scale-1 holder), so cloning from the template yields the same result as cloning from the
  live scaffold in story mode.
- The template has no `NetworkIdentity` and stays inactive, so Mirror scene spawning and
  gameplay are unaffected; it dies with the scene on unload.

## Install

**Every player in the lobby needs this plugin, at the same version.** The GUID starts with
`crackmods.`, so More_Players' own handshake includes it in the `cmods2` lobby token — a peer
without it (or on a different version) is refused at join with a clear reason, exactly like a
More_Players version mismatch.

Copy `MorePlayersIncrementalFix.dll` (plus `manifest.json` / `README.md` for reference) to:

```
<CRACK install>/BepInEx/plugins/crackmods-moreplayers-incrementalfix/
```

If khovanet ships official Incremental support in More_Players, remove this plugin — its
snapshot becomes redundant (and harmless, but keep lobbies consistent).

## Build & deploy

Compiled against the pinned game build (Steam buildid 26883434, Unity 6000.3.9):

```
dotnet build MorePlayersIncrementalFix/MorePlayersIncrementalFix.csproj -c Release   # 0 warnings gate
./scripts/deploy.sh [GameDir]    # default: /mnt/d/SteamLibrary/steamapps/common/CRACK
```

## Test checklist (Incremental host, MaxPlayers=8, AnnexEnabled=true)

In `BepInEx/LogOutput.log`, in order:

1. `More Players Incremental Fix 0.1.0 loaded`
2. `[ModeSetup] incremental: removed N story-only objects...` (Incremental setup ran)
3. `[IncrementalFix] snapshotted the scaffold ladder for More Players' annex...`
4. **no** `[Annex] build failed`
5. `Quarters (Annex)/...` BoxCollider warnings (annex rooms instantiated)
6. `[Lobby check] lobby mods: moreplayers=0.5.2+annex;moreplayers.incrementalfix=0.1.0`

In-world: hatch + ladder in the quarters lobby ceiling; upper floor with 4 more rooms
(name plates over doors). A joiner (own licensed copy, both plugins installed) should spawn
in their own room — the join-refusal handshake must keep refusing peers without the fix.
