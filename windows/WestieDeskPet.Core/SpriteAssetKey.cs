using System;
using System.Collections.Generic;

namespace WestieDeskPet.Core;

public enum SpriteAssetKey
{
    WestieIdle,
    WestieWalk1,
    WestieWalk2,
    WestieWalk3,
    WestieWalk4,
    WestieSitTilt,
    WestieSleep,
    WestieDangling,
    WestiePeekCalm,
    WestiePeekHover,
    WestieLoafCalm,
    WestieChinLedge,

    WestieTopPeekCenter,
    WestieTopPeekLeft,
    WestieTopPeekRight,
    WestieClimbUp,
    WestieYawn,
    WestieDrowsy,

    WestieHopCrouch,
    WestieHopAir,
    WestieHopLand,
    WestieLookLeftHeadLeft,
    WestieLookLeftHeadCenter,
    WestieLookLeftHeadRight,

    WestieFlashStep1,
    WestieFlashStep2,
    WestieFlashStep3,
    WestieFlashStep4,
    WestieFlashStep5,

    WestieEat1,
    WestieEat2,

    WestieHoldingBall,
    WestieTennisReady,
    WestieTennisRun,
    WestieTennisSwing,
    WestieTennisDive,
    WestieVictory,

    PlayerReady,
    PlayerRun,
    PlayerSwing,
    TennisBall,
    BoneTreat,
    BadgeIcon
}

public static class SpriteAssetCatalog
{
    private static readonly Dictionary<SpriteAssetKey, string> BaseNames = new()
    {
        [SpriteAssetKey.WestieIdle] = "westie_idle",
        [SpriteAssetKey.WestieWalk1] = "westie_walk_1",
        [SpriteAssetKey.WestieWalk2] = "westie_walk_2",
        [SpriteAssetKey.WestieWalk3] = "westie_walk_3",
        [SpriteAssetKey.WestieWalk4] = "westie_walk_4",
        [SpriteAssetKey.WestieSitTilt] = "westie_sit_tilt",
        [SpriteAssetKey.WestieSleep] = "westie_sleep",
        [SpriteAssetKey.WestieDangling] = "westie_dangling",
        [SpriteAssetKey.WestiePeekCalm] = "westie_peek_calm",
        [SpriteAssetKey.WestiePeekHover] = "westie_peek_hover",
        [SpriteAssetKey.WestieLoafCalm] = "westie_loaf_calm",
        [SpriteAssetKey.WestieChinLedge] = "westie_chin_ledge",
        [SpriteAssetKey.WestieTopPeekCenter] = "westie_top_peek_center",
        [SpriteAssetKey.WestieTopPeekLeft] = "westie_top_peek_left",
        [SpriteAssetKey.WestieTopPeekRight] = "westie_top_peek_right",
        [SpriteAssetKey.WestieClimbUp] = "westie_climb_up",
        [SpriteAssetKey.WestieYawn] = "westie_yawn",
        [SpriteAssetKey.WestieDrowsy] = "westie_drowsy",
        [SpriteAssetKey.WestieHopCrouch] = "westie_hop_crouch",
        [SpriteAssetKey.WestieHopAir] = "westie_hop_air",
        [SpriteAssetKey.WestieHopLand] = "westie_hop_land",
        [SpriteAssetKey.WestieLookLeftHeadLeft] = "westie_look_left_head_left",
        [SpriteAssetKey.WestieLookLeftHeadCenter] = "westie_look_left_head_center",
        [SpriteAssetKey.WestieLookLeftHeadRight] = "westie_look_left_head_right",
        [SpriteAssetKey.WestieFlashStep1] = "westie_flash_step_1",
        [SpriteAssetKey.WestieFlashStep2] = "westie_flash_step_2",
        [SpriteAssetKey.WestieFlashStep3] = "westie_flash_step_3",
        [SpriteAssetKey.WestieFlashStep4] = "westie_flash_step_4",
        [SpriteAssetKey.WestieFlashStep5] = "westie_flash_step_5",
        [SpriteAssetKey.WestieEat1] = "westie_eat_1",
        [SpriteAssetKey.WestieEat2] = "westie_eat_2",
        [SpriteAssetKey.WestieHoldingBall] = "westie_holding_ball",
        [SpriteAssetKey.WestieTennisReady] = "westie_tennis_ready",
        [SpriteAssetKey.WestieTennisRun] = "westie_tennis_run",
        [SpriteAssetKey.WestieTennisSwing] = "westie_tennis_swing",
        [SpriteAssetKey.WestieTennisDive] = "westie_tennis_dive",
        [SpriteAssetKey.WestieVictory] = "westie_victory",
        [SpriteAssetKey.PlayerReady] = "player_ready",
        [SpriteAssetKey.PlayerRun] = "player_run",
        [SpriteAssetKey.PlayerSwing] = "player_swing",
        [SpriteAssetKey.TennisBall] = "tennis_ball",
        [SpriteAssetKey.BoneTreat] = "bone_treat",
        [SpriteAssetKey.BadgeIcon] = "badge_icon"
    };

    public static IReadOnlyList<SpriteAssetKey> AllKeys { get; } = Enum.GetValues<SpriteAssetKey>();

    public static string GetBaseName(SpriteAssetKey key) => BaseNames[key];

    public static bool IsPetSpecific(SpriteAssetKey key)
    {
        string raw = BaseNames[key];
        return raw.StartsWith("westie_", StringComparison.Ordinal)
            || key == SpriteAssetKey.BadgeIcon
            || key == SpriteAssetKey.BoneTreat;
    }

    public static string GetResourceName(SpriteAssetKey key, PetSpecies species)
    {
        string raw = BaseNames[key];
        if (species == PetSpecies.Westie) return raw;

        if (raw.StartsWith("westie_", StringComparison.Ordinal))
            return "cat_" + raw["westie_".Length..];
        if (key == SpriteAssetKey.BadgeIcon)
            return "cat_badge_icon";
        if (key == SpriteAssetKey.BoneTreat)
            return "dried_fish_treat";
        return raw;
    }
}
