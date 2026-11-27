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
    WestieFlashStep6,
    WestieFlashStep7,
    WestieFlashStep8,

    WestieBearShake1,
    WestieBearShake2,
    WestieBearShake3,
    WestieBearShake4,
    WestieBearShake5,
    WestieBearShake6,
    WestieBearShake7,
    WestieBearShake8,

    WestieWandererKick1,
    WestieWandererKick2,
    WestieWandererKick3,
    WestieWandererKick4,
    WestieWandererKick5,
    WestieWandererKick6,

    WestieBellyRoll1,
    WestieBellyRoll2,
    WestieBellyRoll3,
    WestieBellyRoll4,
    WestieBellyRoll5,
    WestieBellyRoll6,

    WestieHeadTilt1,
    WestieHeadTilt2,
    WestieHeadTilt3,
    WestieHeadTilt4,
    WestieHeadTilt5,
    WestieHeadTilt6,

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
        [SpriteAssetKey.WestieFlashStep6] = "westie_flash_step_6",
        [SpriteAssetKey.WestieFlashStep7] = "westie_flash_step_7",
        [SpriteAssetKey.WestieFlashStep8] = "westie_flash_step_8",
        [SpriteAssetKey.WestieBearShake1] = "westie_bear_shake_1",
        [SpriteAssetKey.WestieBearShake2] = "westie_bear_shake_2",
        [SpriteAssetKey.WestieBearShake3] = "westie_bear_shake_3",
        [SpriteAssetKey.WestieBearShake4] = "westie_bear_shake_4",
        [SpriteAssetKey.WestieBearShake5] = "westie_bear_shake_5",
        [SpriteAssetKey.WestieBearShake6] = "westie_bear_shake_6",
        [SpriteAssetKey.WestieBearShake7] = "westie_bear_shake_7",
        [SpriteAssetKey.WestieBearShake8] = "westie_bear_shake_8",
        [SpriteAssetKey.WestieWandererKick1] = "westie_wanderer_kick_1",
        [SpriteAssetKey.WestieWandererKick2] = "westie_wanderer_kick_2",
        [SpriteAssetKey.WestieWandererKick3] = "westie_wanderer_kick_3",
        [SpriteAssetKey.WestieWandererKick4] = "westie_wanderer_kick_4",
        [SpriteAssetKey.WestieWandererKick5] = "westie_wanderer_kick_5",
        [SpriteAssetKey.WestieWandererKick6] = "westie_wanderer_kick_6",
        [SpriteAssetKey.WestieBellyRoll1] = "westie_belly_roll_1",
        [SpriteAssetKey.WestieBellyRoll2] = "westie_belly_roll_2",
        [SpriteAssetKey.WestieBellyRoll3] = "westie_belly_roll_3",
        [SpriteAssetKey.WestieBellyRoll4] = "westie_belly_roll_4",
        [SpriteAssetKey.WestieBellyRoll5] = "westie_belly_roll_5",
        [SpriteAssetKey.WestieBellyRoll6] = "westie_belly_roll_6",
        [SpriteAssetKey.WestieHeadTilt1] = "westie_head_tilt_1",
        [SpriteAssetKey.WestieHeadTilt2] = "westie_head_tilt_2",
        [SpriteAssetKey.WestieHeadTilt3] = "westie_head_tilt_3",
        [SpriteAssetKey.WestieHeadTilt4] = "westie_head_tilt_4",
        [SpriteAssetKey.WestieHeadTilt5] = "westie_head_tilt_5",
        [SpriteAssetKey.WestieHeadTilt6] = "westie_head_tilt_6",
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

        if (species == PetSpecies.GoldenCat)
        {
            if (raw.StartsWith("westie_", StringComparison.Ordinal))
                return "cat_" + raw["westie_".Length..];
            if (key == SpriteAssetKey.BadgeIcon)
                return "cat_badge_icon";
            if (key == SpriteAssetKey.BoneTreat)
                return "dried_fish_treat";
            return raw;
        }

        if (species == PetSpecies.Labrador)
        {
            if (raw.StartsWith("westie_", StringComparison.Ordinal))
                return "lab_" + raw["westie_".Length..];
            if (key == SpriteAssetKey.BadgeIcon)
                return "lab_badge_icon";
            return raw;
        }

        if (species == PetSpecies.Chinchilla)
        {
            if (raw.StartsWith("westie_", StringComparison.Ordinal))
                return "chinchilla_" + raw["westie_".Length..];
            if (key == SpriteAssetKey.BadgeIcon)
                return "chinchilla_badge_icon";
            if (key == SpriteAssetKey.BoneTreat)
                return "dried_fish_treat";
            return raw;
        }

        if (species == PetSpecies.SilverChinchilla)
        {
            if (raw.StartsWith("westie_", StringComparison.Ordinal))
                return "chinchilla2_" + raw["westie_".Length..];
            if (key == SpriteAssetKey.BadgeIcon)
                return "chinchilla2_badge_icon";
            if (key == SpriteAssetKey.BoneTreat)
                return "dried_fish_treat";
            return raw;
        }

        return raw;
    }
}
