using System;
using BepInEx;
using BepInEx.Logging;
using HarmonyLib;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace MorePlayersIncrementalFix
{
    [BepInPlugin(Guid, Name, Version)]
    [BepInDependency("crackmods.moreplayers")]
    public class Plugin : BaseUnityPlugin
    {
        public const string Guid = "crackmods.moreplayers.incrementalfix";
        public const string Name = "More Players Incremental Fix";
        public const string Version = "0.1.0";

        internal static ManualLogSource Log;

        private void Awake()
        {
            Log = Logger;
            new Harmony(Guid).PatchAll(typeof(Plugin).Assembly);
            Log.LogInfo($"{Name} {Version} loaded");
        }
    }

    // khovanet's More_Players builds its upper-quarters annex by cloning the scaffold
    // ladder from a live "PF_PushScaffold" root (MorePlayers.QuartersAnnex.FindLadderSource:
    // a scene root whose name starts with "PF_PushScaffold" and contains
    // "FBX_Scaffolding_01/SM_Scaffolding_Ladder_01" with a Ladder component).
    //
    // In Incremental mode the game's ModeSetup deletes every PushableScaffold before the
    // annex is built (NetworkServer.SpawnObjects / NetworkClient.PrepareToSpawnSceneObjects),
    // so the clone throws "no scaffold ladder found to copy" and More_Players silently falls
    // back to shared rooms for players 5-8.
    //
    // This prefix snapshots the ladder before ModeSetup runs and re-exposes it as an
    // inactive root with the exact hierarchy FindLadderSource searches for. The snapshot is
    // deterministic, so every peer (host and clients, who run ModeSetup.Apply too) produces
    // the identical template and the annex builds the same everywhere.
    [HarmonyPatch(typeof(ModeSetup), nameof(ModeSetup.Apply))]
    internal static class ModeSetupLadderSnapshotPatch
    {
        private const string ScaffoldRootName = "PF_PushScaffold";
        private const string LadderPath = "FBX_Scaffolding_01/SM_Scaffolding_Ladder_01";

        private static void Prefix(Scene scene)
        {
            try
            {
                SnapshotLadder(scene);
            }
            catch (Exception exception)
            {
                Plugin.Log.LogError("[IncrementalFix] ladder snapshot failed, the annex will fall back to shared rooms: " + exception);
            }
        }

        private static void SnapshotLadder(Scene scene)
        {
            if (GameMode.IsStory)
            {
                return;
            }
            Transform ladder = FindOriginalLadder(scene);
            if (ladder == null)
            {
                Plugin.Log.LogWarning("[IncrementalFix] no scaffold ladder in the scene to snapshot (game update?)");
                return;
            }
            GameObject template = new GameObject(ScaffoldRootName);
            template.AddComponent<SnapshotMarker>();
            template.SetActive(false);
            SceneManager.MoveGameObjectToScene(template, scene);
            GameObject container = new GameObject("FBX_Scaffolding_01");
            container.transform.SetParent(template.transform, false);
            GameObject clone = UnityEngine.Object.Instantiate(ladder.gameObject, container.transform);
            clone.name = "SM_Scaffolding_Ladder_01";
            Plugin.Log.LogInfo("[IncrementalFix] snapshotted the scaffold ladder for More Players' annex (Incremental deletes every PushableScaffold)");
        }

        private static Transform FindOriginalLadder(Scene scene)
        {
            GameObject[] roots = scene.GetRootGameObjects();
            foreach (GameObject root in roots)
            {
                if (root == null || root.GetComponent<SnapshotMarker>() != null || !root.name.StartsWith(ScaffoldRootName, StringComparison.Ordinal))
                {
                    continue;
                }
                Transform ladder = root.transform.Find(LadderPath);
                if (ladder != null && ladder.GetComponentInChildren<Ladder>(true) != null)
                {
                    return ladder;
                }
            }
            return null;
        }
    }

    internal class SnapshotMarker : MonoBehaviour
    {
    }
}
