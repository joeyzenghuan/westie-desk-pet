using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using WestieDeskPet.Core;
using Xunit;

namespace WestieDeskPet.Tests;

public sealed class CoreEngineTests
{
    private static string ResolveSpritesDirectory()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            string candidate = Path.Combine(dir.FullName, "Sources", "WestieDeskPet", "Resources", "Sprites");
            if (Directory.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }
        throw new DirectoryNotFoundException("Could not locate Sources/WestieDeskPet/Resources/Sprites");
    }

    private static (ActiveWorkspaceSnapshot SnapA, ActiveWorkspaceSnapshot SnapB, ActiveWorkspaceSnapshot SnapCOverlap, ActiveWorkspaceSnapshot FullScreenSnap, Size2D SceneSize) BuildFixtures()
    {
        var sceneSize = new Size2D(1440, 932);
        var visible = new Rect2D(0, 60, 1440, 840);
        var winA = new RawWindowInfo(301, 500, "Chrome", new Rect2D(80, 200, 520, 520), IsFrontmostApp: true);
        var winB = new RawWindowInfo(302, 501, "Code", new Rect2D(680, 180, 520, 560), IsFrontmostApp: false);
        var winBFront = winB with { IsFrontmostApp = true };
        var winABack = winA with { IsFrontmostApp = false };
        var winCOverlap = new RawWindowInfo(303, 502, "Notepad", new Rect2D(1120, 200, 300, 600), IsFrontmostApp: true);

        var layoutA = PlatformPhysics.ComputeActiveWindowPerchLayout([winA, winB], sceneSize, visible, 777);
        var snapA = new ActiveWorkspaceSnapshot(
            [], layoutA, [winA, winB],
            new Dictionary<ulong, Rect2D> { [301] = winA.Frame, [302] = winB.Frame },
            sceneSize, visible, "Chrome", false, false, 10.0);

        var layoutB = PlatformPhysics.ComputeActiveWindowPerchLayout([winBFront, winABack], sceneSize, visible, 777);
        var snapB = new ActiveWorkspaceSnapshot(
            [], layoutB, [winBFront, winABack],
            new Dictionary<ulong, Rect2D> { [301] = winABack.Frame, [302] = winBFront.Frame },
            sceneSize, visible, "Code", false, true, 10.0);

        var layoutC = PlatformPhysics.ComputeActiveWindowPerchLayout([winCOverlap, winB], sceneSize, visible, 777);
        var snapC = new ActiveWorkspaceSnapshot(
            [], layoutC, [winCOverlap, winB],
            new Dictionary<ulong, Rect2D> { [302] = winB.Frame, [303] = winCOverlap.Frame },
            sceneSize, visible, "Notepad", false, false, 10.0);

        var fsWin = new RawWindowInfo(202, 600, "PowerPoint", new Rect2D(0, 0, 1440, 932), IsFrontmostApp: true);
        var fsVisible = new Rect2D(0, 0, 1440, 932);
        var fsLayout = PlatformPhysics.ComputeActiveWindowPerchLayout([fsWin], sceneSize, fsVisible, 777);
        var fsSnap = new ActiveWorkspaceSnapshot(
            [], fsLayout, [fsWin],
            new Dictionary<ulong, Rect2D> { [202] = fsWin.Frame },
            sceneSize, fsVisible, "PowerPoint", false, false, 10.0);

        return (snapA, snapB, snapC, fsSnap, sceneSize);
    }

    [Fact]
    public void AllWestieAndGoldenCatSpritesExistWith100PercentParity()
    {
        string spritesDir = ResolveSpritesDirectory();
        var missingWestie = SpriteAssetCatalog.AllKeys
            .Where(k => !File.Exists(Path.Combine(spritesDir, SpriteAssetCatalog.GetResourceName(k, PetSpecies.Westie) + ".png")))
            .ToList();
        Assert.Equal(72, SpriteAssetCatalog.AllKeys.Count);
        Assert.Empty(missingWestie);

        var catKeys = SpriteAssetCatalog.AllKeys.Where(SpriteAssetCatalog.IsPetSpecific).ToList();
        var missingCat = catKeys
            .Where(k => !File.Exists(Path.Combine(spritesDir, SpriteAssetCatalog.GetResourceName(k, PetSpecies.GoldenCat) + ".png")))
            .ToList();
        Assert.Equal(68, catKeys.Count);
        Assert.Empty(missingCat);
        var missingLab = SpriteAssetCatalog.AllKeys
            .Where(k => !File.Exists(Path.Combine(spritesDir, SpriteAssetCatalog.GetResourceName(k, PetSpecies.Labrador) + ".png")))
            .ToList();
        Assert.Empty(missingLab);
        var missingChinchilla = SpriteAssetCatalog.AllKeys
            .Where(k => !File.Exists(Path.Combine(spritesDir, SpriteAssetCatalog.GetResourceName(k, PetSpecies.Chinchilla) + ".png")))
            .ToList();
        Assert.Empty(missingChinchilla);
        Assert.Equal("dried_fish_treat", SpriteAssetCatalog.GetResourceName(SpriteAssetKey.BoneTreat, PetSpecies.GoldenCat));
        Assert.Equal("dried_fish_treat", SpriteAssetCatalog.GetResourceName(SpriteAssetKey.BoneTreat, PetSpecies.Chinchilla));
        Assert.Equal("bone_treat", SpriteAssetCatalog.GetResourceName(SpriteAssetKey.BoneTreat, PetSpecies.Labrador));
    }

    [Fact]
    public void WindowPlatformOcclusionAndMultiMonitorLayoutWorkCleanly()
    {
        var visible = new Rect2D(0, 60, 1440, 840);
        var frontWin = new RawWindowInfo(101, 500, "Code", new Rect2D(200, 300, 400, 420), IsFrontmostApp: true);
        var backWin = new RawWindowInfo(102, 501, "Terminal", new Rect2D(400, 200, 500, 400), IsFrontmostApp: false);
        var ownWin = new RawWindowInfo(999, 777, "WestieDeskPet", new Rect2D(0, 0, 1440, 900), IsFrontmostApp: false);

        var platforms = PlatformPhysics.ExtractVisiblePlatforms([ownWin, frontWin, backWin], visible, 777);
        Assert.DoesNotContain(platforms, p => p.WindowId == 999);
        Assert.Equal(720, platforms.First(p => p.WindowId == 101).Y);
        Assert.True(platforms.First(p => p.WindowId == 102).MinX >= 600);
        Assert.Contains(platforms, p => p.IsDockFloor);

        // Secondary monitor with zero taskbar/menu bar is NOT misclassified as fullscreen!
        var extSize = new Size2D(2560, 1440);
        var extVisible = new Rect2D(0, 0, 2560, 1440);
        var extWin = new RawWindowInfo(401, 505, "Chrome", new Rect2D(200, 200, 1200, 900), IsFrontmostApp: true);
        var extLayout = PlatformPhysics.ComputeActiveWindowPerchLayout([extWin], extSize, extVisible, 777);
        Assert.False(extLayout.IsFullScreenMode);
        Assert.NotNull(extLayout.TopPerch);
        Assert.NotNull(extLayout.WindowRightPeek);
    }

    [Fact]
    public void DampedSpringOvershootsAndSettlesCleanly()
    {
        var spring = new DampedSpring(value: 0, target: 1.0, stiffness: 320, damping: 22);
        double peak = 0;
        for (int i = 0; i < 120; i++)
        {
            spring.Step(1.0 / 120.0);
            peak = Math.Max(peak, spring.Value);
        }
        Assert.True(peak > 1.01);
        Assert.True(spring.IsSettled);
        Assert.True(Math.Abs(spring.Value - 1.0) < 0.002);
    }

    [Fact]
    public void DefaultScreenRightModeAndOptInWindowRightStealthDwellWork()
    {
        var (snapA, snapB, snapC, _, sceneSize) = BuildFixtures();
        var freshDefaults = new CompanionPreferences(storagePath: null);
        Assert.Equal(PerchPreference.Auto, freshDefaults.PerchPreference);
        Assert.Equal(15.0, freshDefaults.WindowSwitchDelaySeconds);
        Assert.Equal(300.0, freshDefaults.ClimbToTopIntervalSeconds);
        Assert.Equal(900.0, freshDefaults.TopEffectIntervalSeconds);
        Assert.Equal(1.50, freshDefaults.DogScale, 3);

        var prefs = new CompanionPreferences(storagePath: null)
        {
            WindowSwitchDelaySeconds = 5.0,
            PerchPreference = PerchPreference.Auto,
            DogScale = 1.0
        };

        var autoPet = new CompanionEngine(prefs, ownPid: 777);
        autoPet.PlaceInitially(snapA, sceneSize);
        Assert.Equal(PerchZone.ScreenRightPeek, autoPet.PerchZone);
        Assert.Equal(301UL, autoPet.TrackedWindowId);

        // Tight right-peek hover trigger: distant cursor (65pt) does NOT hit; close head (18pt) hits!
        Assert.False(autoPet.InteractiveHitRect().Contains(new Vec2(autoPet.Position.X - 65, autoPet.Position.Y)));
        Assert.True(autoPet.InteractiveHitRect().Contains(new Vec2(autoPet.Position.X - 18, autoPet.Position.Y + 6)));

        // Switching window in default mode stays calmly on screen right bezel
        for (int i = 0; i < 20; i++) autoPet.Update(0.05, snapB, sceneSize);
        Assert.Equal(PerchZone.ScreenRightPeek, autoPet.PerchZone);
        Assert.Equal(302UL, autoPet.TrackedWindowId);

        // Opt-in window-right mode: 5s dwell debounce + same-Y shortest path + overlap early tuck
        prefs.PerchPreference = PerchPreference.RightPeek;
        var winRightPet = new CompanionEngine(prefs, ownPid: 777);
        winRightPet.PlaceInitially(snapA, sceneSize);
        double startY = winRightPet.Position.Y;
        Assert.Equal(PerchZone.WindowRightPeek, winRightPet.PerchZone);

        for (int i = 0; i < 60; i++) winRightPet.Update(0.05, snapB, sceneSize); // 3s < 5s
        Assert.Equal(301UL, winRightPet.TrackedWindowId);
        Assert.Equal(302UL, winRightPet.PendingWindowSwitch?.TargetWindowId);

        bool sawRetract = false, sawHidden = false, sawPeek = false;
        for (int i = 0; i < 120; i++)
        {
            winRightPet.Update(0.05, snapB, sceneSize);
            if (winRightPet.StateKind == CompanionStateKind.StealthTransition)
            {
                if (winRightPet.StealthPhase == StealthPhaseKind.Retracting) sawRetract = true;
                if (winRightPet.StealthPhase == StealthPhaseKind.HiddenTraverse) sawHidden = true;
                if (winRightPet.StealthPhase == StealthPhaseKind.TentativePeek) sawPeek = true;
            }
        }
        Assert.True(sawRetract && sawHidden && sawPeek);
        Assert.Equal(302UL, winRightPet.TrackedWindowId);
        Assert.Equal(PerchZone.WindowRightPeek, winRightPet.PerchZone);
        Assert.True(Math.Abs(winRightPet.Position.Y - startY) < 1.5);

        // Overlap early-tuck (`tuck_early`)
        for (int i = 0; i < 8; i++) winRightPet.Update(0.05, snapC, sceneSize);
        Assert.Equal(CompanionStateKind.TuckedWaiting, winRightPet.StateKind);
        Assert.True(winRightPet.InteractiveHitRect().IsEmpty);
    }

    [Fact]
    public void FullScreenFromWindowTopDucksInPlaceWithoutCornerTeleport()
    {
        var (_, snapB, _, fsSnap, sceneSize) = BuildFixtures();
        var prefs = new CompanionPreferences(storagePath: null) { PerchPreference = PerchPreference.WindowTop };
        var pet = new CompanionEngine(prefs, ownPid: 777);
        pet.PlaceInitially(snapB, sceneSize);
        double xBefore = pet.Position.X;

        bool teleported = false;
        for (int i = 0; i < 60; i++)
        {
            pet.Update(0.05, fsSnap, sceneSize);
            if (pet.StateKind == CompanionStateKind.StealthTransition &&
                pet.StealthPhase == StealthPhaseKind.Retracting &&
                Math.Abs(pet.Position.X - xBefore) > 1.0)
            {
                teleported = true;
            }
        }

        Assert.False(teleported);
        Assert.Equal(PerchZone.ScreenRightPeek, pet.PerchZone);
        Assert.Equal(1440.0, pet.Position.X);
    }

    [Fact]
    public void InitialPeekPoseIndependentEffectsPeriodicTriggerAndTapPosesWork()
    {
        var (_, snapB, _, _, sceneSize) = BuildFixtures();
        var snapTyping = new ActiveWorkspaceSnapshot(
            snapB.Platforms, snapB.PerchLayout, snapB.WindowsFrontToBack, snapB.WindowFramesById,
            snapB.ScreenSize, snapB.VisibleScreenFrame, snapB.FrontmostAppName, false, true, secondsSinceLastKeyDown: 0.4);

        var prefs = new CompanionPreferences(storagePath: null)
        {
            PerchPreference = PerchPreference.Auto,
            ClimbToTopEnabled = true,
            ClimbToTopIntervalSeconds = 3.0,
            TopEffectsEnabled = true,
            TopEffectIntervalSeconds = 15.0,
            TypingPauseEnabled = true
        };
        Assert.Equal(3.0, prefs.ClimbToTopIntervalSeconds);

        var pet = new CompanionEngine(prefs, ownPid: 777);
        pet.PlaceInitially(snapB, sceneSize);

        // Typing pause defers climb even past 3s
        for (int i = 0; i < 100; i++) pet.Update(0.05, snapTyping, sceneSize);
        Assert.Equal(PerchZone.ScreenRightPeek, pet.PerchZone);

        // Stop typing -> climbs to top, peeks left/right, and rests seamlessly in head-on-ledge forward pose (ChinRest)!
        bool landedInChinRest = false;
        for (int i = 0; i < 160; i++)
        {
            pet.Update(0.05, snapB, sceneSize);
            if (pet.PerchZone == PerchZone.WindowTop && pet.StateKind == CompanionStateKind.ChinRest)
            {
                landedInChinRest = true;
                break;
            }
        }
        Assert.True(landedInChinRest);

        // Independent Effect 1: Patrol (rises from peek -> hopLeft -> lookAround -> walkRight -> smileSit -> calm SitCalm, NO auto yawn!)
        pet.TriggerTopBarEffect(TopBarEffect.Patrol, snapB, sceneSize);
        bool sawRise = false, sawHop = false, sawLook = false, sawWalkR = false, sawSmile = false, patrolFinishedSit = false, sawUnwantedYawn = false;
        for (int i = 0; i < 420; i++)
        {
            pet.Update(0.05, snapB, sceneSize);
            if (pet.StateKind == CompanionStateKind.TopStory)
            {
                if (pet.TopStoryStep == TopStoryStepKind.RisingToFullBody) sawRise = true;
                if (pet.TopStoryStep == TopStoryStepKind.HopLeft) sawHop = true;
                if (pet.TopStoryStep == TopStoryStepKind.LookAroundPause && sawHop) sawLook = true;
                if (pet.TopStoryStep == TopStoryStepKind.WalkRight && sawLook) sawWalkR = true;
                if (pet.TopStoryStep == TopStoryStepKind.SmileSit && sawWalkR) sawSmile = true;
            }
            else if (pet.StateKind == CompanionStateKind.Yawning) sawUnwantedYawn = true;
            else if (pet.StateKind == CompanionStateKind.SitCalm && sawSmile) { patrolFinishedSit = true; break; }
        }
        Assert.True(sawRise && sawHop && sawLook && sawWalkR && sawSmile && patrolFinishedSit && !sawUnwantedYawn);

        // Independent Effect 3: YawnSleep (yawn -> drowsy -> sleep)
        pet.TriggerTopBarEffect(TopBarEffect.YawnSleep, snapB, sceneSize);
        bool sawYawn = false, sawDrowsy = false, sawSleep = false;
        for (int i = 0; i < 240; i++)
        {
            pet.Update(0.05, snapB, sceneSize);
            if (pet.StateKind == CompanionStateKind.Yawning) sawYawn = true;
            else if (pet.StateKind == CompanionStateKind.SettlingToSleep && sawYawn) sawDrowsy = true;
            else if (pet.StateKind == CompanionStateKind.Sleeping && sawDrowsy) { sawSleep = true; break; }
        }
        Assert.True(sawYawn && sawDrowsy && sawSleep);

        // Unified top-bar hover does NOT wake sleeping pet; tap cycles sitSmile -> loafCalm -> bigHeadPeek!
        pet.SetHovering(true, pointerSpeed: 60, nearZone: true);
        pet.Update(0.05, snapB, sceneSize);
        Assert.Equal(CompanionStateKind.Sleeping, pet.StateKind);

        var tapPt = new Vec2(pet.Position.X, pet.Position.Y + 20);
        Assert.True(pet.HandleMouseDown(tapPt));
        pet.HandleMouseUp(tapPt, snapB, sceneSize);
        Assert.Equal(CompanionStateKind.SitCalm, pet.StateKind);

        Assert.True(pet.HandleMouseDown(tapPt));
        pet.HandleMouseUp(tapPt, snapB, sceneSize);
        Assert.Equal(CompanionStateKind.Loafing, pet.StateKind);

        Assert.True(pet.HandleMouseDown(tapPt));
        pet.HandleMouseUp(tapPt, snapB, sceneSize);
        Assert.Equal(CompanionStateKind.ChinRest, pet.StateKind);

        // Periodic auto-trigger: resting in initial ChinRest for TopEffectIntervalSeconds fires enabled effect!
        prefs.TopEffectIntervalSeconds = 5.0;
        prefs.SetEnabledTopEffects([TopBarEffect.FlashStep]);
        var autoPet = new CompanionEngine(prefs, ownPid: 777);
        autoPet.PlaceInitially(snapB, sceneSize);
        autoPet.MoveImmediatelyToZone(PerchZone.WindowTop, snapB, sceneSize);
        bool autoFired = false;
        for (int i = 0; i < 240; i++)
        {
            autoPet.Update(0.05, snapB, sceneSize);
            if (autoPet.StateKind == CompanionStateKind.TopStory && autoPet.TopStoryStep == TopStoryStepKind.FlashStep)
            {
                autoFired = true;
                break;
            }
        }
        prefs.ClimbToTopIntervalSeconds = 3600.0;
        Assert.Equal(3600.0, prefs.ClimbToTopIntervalSeconds);
        Assert.Equal("45 分钟", CompanionPreferences.FormatDuration(2700));
        prefs.TopEffectIntervalSeconds = 3600.0;
        Assert.Equal(3600.0, prefs.TopEffectIntervalSeconds);
        Assert.Equal("15 分钟", CompanionPreferences.FormatDuration(900));
        Assert.Equal("30 分钟", CompanionPreferences.FormatDuration(1800));
        Assert.Equal("1 小时", CompanionPreferences.FormatDuration(3600));
        Assert.True(autoFired);
    }

    [Fact]
    public void GoldenCatFlashStepDanceAndDriedFishEatingWorkEndToEnd()
    {
        var (_, snapB, _, _, sceneSize) = BuildFixtures();
        var prefs = new CompanionPreferences(storagePath: null)
        {
            PetSpecies = PetSpecies.GoldenCat,
            DogScale = 1.5
        };
        var cat = new CompanionEngine(prefs, ownPid: 777);
        cat.PlaceInitially(snapB, sceneSize);

        cat.TriggerTopBarEffect(TopBarEffect.FlashStep, snapB, sceneSize);

        bool s1 = false, s2 = false, s3 = false, s4 = false, s5 = false, s6 = false, s7 = false, flashFinishedToSit = false;
        for (int i = 0; i < 500; i++)
        {
            cat.Update(0.05, snapB, sceneSize);
            if (cat.StateKind == CompanionStateKind.TopStory && cat.TopStoryStep == TopStoryStepKind.FlashStep)
            {
                if (cat.FlashStepBeat == FlashStepBeatKind.SplitFeintLeft) s1 = true;
                if (cat.FlashStepBeat == FlashStepBeatKind.GlideWideLeft && s1) s2 = true;
                if (cat.FlashStepBeat == FlashStepBeatKind.SnapCloseLeft && s2) s3 = true;
                if (cat.FlashStepBeat == FlashStepBeatKind.StatueFreezeLeft && s3) s4 = true;
                if (cat.FlashStepBeat == FlashStepBeatKind.SplitFeintRight && s4) s5 = true;
                if (cat.FlashStepBeat == FlashStepBeatKind.GlideWideRight && s5) s6 = true;
                if (cat.FlashStepBeat == FlashStepBeatKind.SnapCloseRight && s6) s7 = true;
            }
            else if (cat.StateKind == CompanionStateKind.SitCalm && s7)
            {
                flashFinishedToSit = true;
                break;
            }
        }
        Assert.True(s1 && s2 && s3 && s4 && s5 && s6 && s7 && flashFinishedToSit);

        // New independent effects: BearShake, WandererKick, HeadTilt, and WindowRoll (right -> left -> right)!
        cat.TriggerTopBarEffect(TopBarEffect.BearShake, snapB, sceneSize);
        bool sawBear = false, bearDone = false;
        for (int i = 0; i < 260; i++)
        {
            cat.Update(0.05, snapB, sceneSize);
            if (cat.StateKind == CompanionStateKind.TopStory && cat.TopStoryStep == TopStoryStepKind.BearShake) sawBear = true;
            else if (cat.StateKind == CompanionStateKind.SitCalm && sawBear) { bearDone = true; break; }
        }
        Assert.True(sawBear && bearDone);

        cat.TriggerTopBarEffect(TopBarEffect.WandererKick, snapB, sceneSize);
        bool sawKick = false, kickDone = false;
        for (int i = 0; i < 260; i++)
        {
            cat.Update(0.05, snapB, sceneSize);
            if (cat.StateKind == CompanionStateKind.TopStory && cat.TopStoryStep == TopStoryStepKind.WandererKick) sawKick = true;
            else if (cat.StateKind == CompanionStateKind.SitCalm && sawKick) { kickDone = true; break; }
        }
        Assert.True(sawKick && kickDone);

        cat.TriggerTopBarEffect(TopBarEffect.HeadTilt, snapB, sceneSize);
        bool sawTilt = false, tiltDone = false;
        for (int i = 0; i < 180; i++)
        {
            cat.Update(0.05, snapB, sceneSize);
            if (cat.StateKind == CompanionStateKind.TopStory && cat.TopStoryStep == TopStoryStepKind.HeadTilt) sawTilt = true;
            else if (cat.StateKind == CompanionStateKind.SitCalm && sawTilt) { tiltDone = true; break; }
        }
        Assert.True(sawTilt && tiltDone);

        cat.TriggerTopBarEffect(TopBarEffect.WindowRoll, snapB, sceneSize);
        bool reachedWaitA = false;
        for (int i = 0; i < 20; i++)
        {
            cat.Update(0.05, snapB, sceneSize);
            if (cat.StateKind == CompanionStateKind.TopStory && cat.TopStoryStep == TopStoryStepKind.BellyRoll &&
                cat.BellyRollPhase == BellyRollPhaseKind.WaitingBellyUp && cat.BellyRollSideSign > 0)
            {
                reachedWaitA = true;
                break;
            }
        }
        for (int i = 0; i < 120; i++) cat.Update(0.05, snapB, sceneSize); // 6s < 10s
        var clickPt = new Vec2(cat.Position.X, cat.Position.Y + 20);
        Assert.True(cat.HandleMouseDown(clickPt));
        cat.HandleMouseUp(clickPt, snapB, sceneSize);
        bool sawFlip = false, flippedSideB = false;
        for (int i = 0; i < 40; i++)
        {
            cat.Update(0.05, snapB, sceneSize);
            if (cat.StateKind == CompanionStateKind.TopStory && cat.TopStoryStep == TopStoryStepKind.BellyRoll)
            {
                if (cat.BellyRollPhase == BellyRollPhaseKind.RollingOver) sawFlip = true;
                if (cat.BellyRollPhase == BellyRollPhaseKind.WaitingBellyUp && cat.BellyRollSideSign < 0)
                {
                    flippedSideB = true;
                    break;
                }
            }
        }
        bool endedAfter10s = false;
        for (int i = 0; i < 230; i++)
        {
            cat.Update(0.05, snapB, sceneSize);
            if (cat.StateKind == CompanionStateKind.SitCalm) { endedAfter10s = true; break; }
        }
        Assert.True(reachedWaitA && sawFlip && flippedSideB && endedAfter10s);

        // Feed dried fish -> chase -> chewing eatingTreat -> happy sitCalm!
        cat.DropSnackTreat(snapB, sceneSize);
        Assert.True(cat.LatestRender.Treat.IsVisible || cat.StateKind == CompanionStateKind.ChasingTreat);
        bool sawEating = false, finishedToSit = false;
        for (int i = 0; i < 160; i++)
        {
            cat.Update(0.05, snapB, sceneSize);
            if (cat.StateKind == CompanionStateKind.EatingTreat) sawEating = true;
            else if (cat.StateKind == CompanionStateKind.SitCalm && sawEating) { finishedToSit = true; break; }
        }
        Assert.True(sawEating && finishedToSit);
    }

    [Fact]
    public void FallbackToScreenRightWhileOccludedNeverDeadlocksInTuckedWaiting()
    {
        var (snapA, _, _, _, sceneSize) = BuildFixtures();
        var visible = new Rect2D(0, 60, 1440, 840);
        var prefs = new CompanionPreferences(storagePath: null)
        {
            PerchPreference = PerchPreference.Auto,
            WindowSwitchDelaySeconds = 5.0
        };
        var pet = new CompanionEngine(prefs, ownPid: 777);
        pet.PlaceInitially(snapA, sceneSize);
        pet.MoveImmediatelyToZone(PerchZone.WindowTop, snapA, sceneSize);
        for (int i = 0; i < 110; i++) pet.Update(0.05, snapA, sceneSize);

        var winAFlushTop = new RawWindowInfo(301, 500, "Chrome", new Rect2D(80, 120, 600, 780), IsFrontmostApp: false);
        var winDRightFlush = new RawWindowInfo(304, 509, "RightApp", new Rect2D(700, 100, 740, 740), IsFrontmostApp: true);
        var layoutD = PlatformPhysics.ComputeActiveWindowPerchLayout([winDRightFlush, winAFlushTop], sceneSize, visible, 777);
        var snapD = new ActiveWorkspaceSnapshot(
            [], layoutD, [winDRightFlush, winAFlushTop],
            new Dictionary<ulong, Rect2D> { [301] = winAFlushTop.Frame, [304] = winDRightFlush.Frame },
            sceneSize, visible, "RightApp", false, false, 10.0);

        for (int i = 0; i < 25; i++) pet.Update(0.05, snapD, sceneSize);

        Assert.Equal(PerchZone.ScreenRightPeek, pet.PerchZone);
        Assert.NotEqual(CompanionStateKind.TuckedWaiting, pet.StateKind);
        Assert.False(pet.InteractiveHitRect().IsEmpty);
    }

    [Fact]
    public void Tennis25DPhysicsDropShotBackspinAndCatAIWork()
    {
        // Charged topspin clears net & bounces in opponent half
        var topspin = TennisPhysics.MakeShot(20, -205, 24, CourtSide.Player, new Vec2(-85, 175), TennisShotKind.ChargedTopspin, 0.8);
        bool bouncedInOpp = false;
        for (int i = 0; i < 240; i++)
        {
            var res = TennisPhysics.StepBall(ref topspin, 1.0 / 60.0);
            if (res.Bounced && topspin.Y > 0) { bouncedInOpp = true; break; }
        }
        Assert.True(topspin.HasCrossedNet && bouncedInOpp);

        // Drop-shot backspin brakes horizontal velocity on bounce
        var drop = TennisPhysics.MakeShot(0, -120, 24, CourtSide.Player, new Vec2(35, 55), TennisShotKind.DropShot, 0.2);
        double preSpeed = Vec2.Hypot(drop.Vx, drop.Vy);
        double postSpeed = preSpeed;
        for (int i = 0; i < 180; i++)
        {
            var res = TennisPhysics.StepBall(ref drop, 1.0 / 60.0);
            if (res.Bounced) { postSpeed = Vec2.Hypot(drop.Vx, drop.Vy); break; }
        }
        Assert.True(postSpeed < preSpeed * 0.65);

        // AI predicts landing and returns shot
        var rally = TennisPhysics.MakeShot(0, -200, 24, CourtSide.Player, new Vec2(35, 170), TennisShotKind.FlatDrive, 0.3);
        var opp = WestieOpponentState.CreateDefault();
        bool returned = false;
        for (int i = 0; i < 240; i++)
        {
            TennisPhysics.StepBall(ref rally, 1.0 / 60.0);
            if (WestieTennisAI.Step(ref opp, ref rally, true, new Vec2(0, -205), TennisDifficulty.Pro, 1.0 / 60.0))
            {
                returned = true;
                break;
            }
        }
        Assert.True(returned && rally.LastHitter == CourtSide.Westie && rally.Vy < 0);

        // Species-aware tennis UI text
        var prefs = new CompanionPreferences(storagePath: null) { PetSpecies = PetSpecies.GoldenCat };
        var match = new TennisMatchEngine(prefs);
        match.StartMatch();
        Assert.Contains("金渐层", match.ScoreboardText);
        Assert.Contains("休闲小猫", match.DifficultyPillText);
    }
}
