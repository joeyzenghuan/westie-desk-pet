using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WestieDeskPet.Core;

public sealed class CompanionPreferences
{
    public static readonly (string Title, double Seconds)[] SwitchDelayPresets =
    [
        ("立即跟随 (0 秒)", 0),
        ("3 秒", 3),
        ("5 秒", 5),
        ("10 秒", 10),
        ("15 秒 (默认)", 15)
    ];

    public static readonly (string Title, bool Enabled, double Seconds)[] ClimbIntervalPresets =
    [
        ("3 秒 (快速测试)", true, 3),
        ("15 秒", true, 15),
        ("30 秒", true, 30),
        ("1 分钟", true, 60),
        ("3 分钟", true, 180),
        ("5 分钟 (默认)", true, 300),
        ("10 分钟", true, 600),
        ("15 分钟", true, 900),
        ("30 分钟", true, 1800),
        ("45 分钟", true, 2700),
        ("60 分钟 (1 小时)", true, 3600),
        ("关闭自动爬顶", false, 300)
    ];

    public static readonly (string Title, bool Enabled, double Seconds)[] EffectIntervalPresets =
    [
        ("5 秒 (快速测试)", true, 5),
        ("15 秒", true, 15),
        ("45 秒", true, 45),
        ("3 分钟", true, 180),
        ("5 分钟", true, 300),
        ("15 分钟 (默认)", true, 900),
        ("30 分钟", true, 1800),
        ("1 小时", true, 3600),
        ("关闭定时特效", false, 900)
    ];

    public static readonly (string Title, double Scale)[] DogScalePresets =
    [
        ("迷你 (75%)", 0.75),
        ("标准 (100%)", 1.0),
        ("大只 (125%)", 1.25),
        ("超大 (150% 默认)", 1.50)
    ];

    private sealed class PersistedDto
    {
        public double WindowSwitchDelaySeconds { get; set; } = 15.0;
        public bool ClimbToTopEnabled { get; set; } = true;
        public double ClimbToTopIntervalSeconds { get; set; } = 300.0;
        public bool TopEffectsEnabled { get; set; } = true;
        public double TopEffectIntervalSeconds { get; set; } = 900.0;
        public List<TopBarEffect>? EnabledTopEffects { get; set; }
        public bool ShyRetreatEnabled { get; set; } = true;
        public bool TypingPauseEnabled { get; set; } = true;
        public bool ClimbPawsPeekEnabled { get; set; } = true;
        public double DogScale { get; set; } = 1.50;
        public List<TopTapPose>? TopTapEnabledPoses { get; set; }
        public PetSpecies PetSpecies { get; set; } = PetSpecies.Westie;
        public PerchPreference PerchPreference { get; set; } = PerchPreference.Auto;
        public TennisGameSpeed TennisSpeed { get; set; } = TennisGameSpeed.Slow;
        public TennisDifficulty TennisDifficulty { get; set; } = TennisDifficulty.Casual;
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    private readonly string? _storagePath;
    private bool _suppressSave;

    private double _windowSwitchDelaySeconds = 15.0;
    private bool _climbToTopEnabled = true;
    private double _climbToTopIntervalSeconds = 300.0;
    private bool _topEffectsEnabled = true;
    private double _topEffectIntervalSeconds = 900.0;
    private HashSet<TopBarEffect> _enabledTopEffects = new(TopBarEffectExtensions.DefaultSelection);
    private bool _shyRetreatEnabled = true;
    private bool _typingPauseEnabled = true;
    private bool _climbPawsPeekEnabled = true;
    private double _dogScale = 1.50;
    private HashSet<TopTapPose> _topTapEnabledPoses = new(TopTapPoseExtensions.DefaultSelection);
    private PetSpecies _petSpecies = PetSpecies.Westie;
    private PerchPreference _perchPreference = PerchPreference.Auto;
    private TennisGameSpeed _tennisSpeed = TennisGameSpeed.Slow;
    private TennisDifficulty _tennisDifficulty = TennisDifficulty.Casual;

    public event Action? Changed;

    public static CompanionPreferences Shared { get; } = new(GetDefaultStoragePath());

    public CompanionPreferences(string? storagePath = null)
    {
        _storagePath = storagePath;
        Load();
    }

    public static string GetDefaultStoragePath()
    {
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrWhiteSpace(appData))
            appData = Path.GetTempPath();
        return Path.Combine(appData, "WestieDeskPet", "preferences.json");
    }

    public double WindowSwitchDelaySeconds
    {
        get => _windowSwitchDelaySeconds;
        set { _windowSwitchDelaySeconds = Math.Clamp(value, 0, 30); NotifyAndSave(); }
    }

    public bool ClimbToTopEnabled
    {
        get => _climbToTopEnabled;
        set { _climbToTopEnabled = value; NotifyAndSave(); }
    }

    public double ClimbToTopIntervalSeconds
    {
        get => _climbToTopIntervalSeconds;
        set { _climbToTopIntervalSeconds = Math.Clamp(value, 3, 3600); NotifyAndSave(); }
    }

    public bool TopEffectsEnabled
    {
        get => _topEffectsEnabled;
        set { _topEffectsEnabled = value; NotifyAndSave(); }
    }

    public double TopEffectIntervalSeconds
    {
        get => _topEffectIntervalSeconds;
        set { _topEffectIntervalSeconds = Math.Clamp(value, 5, 3600); NotifyAndSave(); }
    }

    public IReadOnlyList<TopBarEffect> OrderedEnabledTopEffects
    {
        get
        {
            var list = Enum.GetValues<TopBarEffect>().Where(e => _enabledTopEffects.Contains(e)).ToList();
            return list.Count > 0 ? list : [TopBarEffect.Patrol];
        }
    }

    public bool IsTopEffectEnabled(TopBarEffect effect) => _enabledTopEffects.Contains(effect);

    public void SetTopEffect(TopBarEffect effect, bool enabled)
    {
        if (enabled)
        {
            _enabledTopEffects.Add(effect);
            NotifyAndSave();
        }
        else if (_enabledTopEffects.Count > 1 && _enabledTopEffects.Remove(effect))
        {
            NotifyAndSave();
        }
    }

    public void SetEnabledTopEffects(IEnumerable<TopBarEffect> effects)
    {
        var set = new HashSet<TopBarEffect>(effects);
        if (set.Count == 0) set.Add(TopBarEffect.Patrol);
        _enabledTopEffects = set;
        NotifyAndSave();
    }

    public bool ShyRetreatEnabled
    {
        get => _shyRetreatEnabled;
        set { _shyRetreatEnabled = value; NotifyAndSave(); }
    }

    public bool TypingPauseEnabled
    {
        get => _typingPauseEnabled;
        set { _typingPauseEnabled = value; NotifyAndSave(); }
    }

    public bool ClimbPawsPeekEnabled
    {
        get => _climbPawsPeekEnabled;
        set { _climbPawsPeekEnabled = value; NotifyAndSave(); }
    }

    public double DogScale
    {
        get => _dogScale;
        set { _dogScale = Math.Clamp(value, 0.60, 1.60); NotifyAndSave(); }
    }

    public PetSpecies PetSpecies
    {
        get => _petSpecies;
        set { _petSpecies = value; NotifyAndSave(); }
    }

    public PerchPreference PerchPreference
    {
        get => _perchPreference;
        set { _perchPreference = value; NotifyAndSave(); }
    }

    public TennisGameSpeed TennisSpeed
    {
        get => _tennisSpeed;
        set { _tennisSpeed = value; NotifyAndSave(); }
    }

    public TennisDifficulty TennisDifficulty
    {
        get => _tennisDifficulty;
        set { _tennisDifficulty = value; NotifyAndSave(); }
    }

    public IReadOnlyList<TopTapPose> OrderedEnabledTopTapPoses
    {
        get
        {
            var list = Enum.GetValues<TopTapPose>().Where(p => _topTapEnabledPoses.Contains(p)).ToList();
            return list.Count > 0 ? list : [TopTapPose.SitSmile];
        }
    }

    public bool IsTopTapPoseEnabled(TopTapPose pose) => _topTapEnabledPoses.Contains(pose);

    public void SetTopTapPose(TopTapPose pose, bool enabled)
    {
        if (enabled)
        {
            _topTapEnabledPoses.Add(pose);
            NotifyAndSave();
        }
        else if (_topTapEnabledPoses.Count > 1 && _topTapEnabledPoses.Remove(pose))
        {
            NotifyAndSave();
        }
    }

    public void ResetToDefaults()
    {
        _suppressSave = true;
        _windowSwitchDelaySeconds = 15.0;
        _climbToTopEnabled = true;
        _climbToTopIntervalSeconds = 300.0;
        _topEffectsEnabled = true;
        _topEffectIntervalSeconds = 900.0;
        _enabledTopEffects = new HashSet<TopBarEffect>(TopBarEffectExtensions.DefaultSelection);
        _shyRetreatEnabled = true;
        _typingPauseEnabled = true;
        _climbPawsPeekEnabled = true;
        _dogScale = 1.50;
        _topTapEnabledPoses = new HashSet<TopTapPose>(TopTapPoseExtensions.DefaultSelection);
        _petSpecies = PetSpecies.Westie;
        _perchPreference = PerchPreference.Auto;
        _tennisSpeed = TennisGameSpeed.Slow;
        _tennisDifficulty = TennisDifficulty.Casual;
        _suppressSave = false;
        NotifyAndSave();
    }

    public static string FormatDuration(double seconds)
    {
        int rounded = (int)Math.Round(seconds);
        if (rounded == 0) return "立即";
        if (rounded >= 3600 && rounded % 3600 == 0) return $"{rounded / 3600} 小时";
        if (rounded > 3600) return $"{rounded / 3600} 小时 {(rounded % 3600) / 60} 分钟";
        if (rounded >= 60 && rounded % 60 == 0) return $"{rounded / 60} 分钟";
        if (rounded > 60) return $"{rounded / 60} 分 {rounded % 60} 秒";
        return $"{rounded} 秒";
    }

    public static string FormatScale(double scale) => $"{(int)Math.Round(scale * 100.0)}%";

    private void Load()
    {
        if (string.IsNullOrWhiteSpace(_storagePath) || !File.Exists(_storagePath))
            return;

        try
        {
            string json = File.ReadAllText(_storagePath);
            var dto = JsonSerializer.Deserialize<PersistedDto>(json, JsonOptions);
            if (dto is null) return;

            _suppressSave = true;
            _windowSwitchDelaySeconds = Math.Clamp(dto.WindowSwitchDelaySeconds, 0, 30);
            _climbToTopEnabled = dto.ClimbToTopEnabled;
            _climbToTopIntervalSeconds = Math.Clamp(dto.ClimbToTopIntervalSeconds, 3, 3600);
            _topEffectsEnabled = dto.TopEffectsEnabled;
            _topEffectIntervalSeconds = Math.Clamp(dto.TopEffectIntervalSeconds, 5, 3600);
            if (dto.EnabledTopEffects is { Count: > 0 })
                _enabledTopEffects = new HashSet<TopBarEffect>(dto.EnabledTopEffects);
            _shyRetreatEnabled = dto.ShyRetreatEnabled;
            _typingPauseEnabled = dto.TypingPauseEnabled;
            _climbPawsPeekEnabled = dto.ClimbPawsPeekEnabled;
            _dogScale = Math.Clamp(dto.DogScale, 0.60, 1.60);
            if (dto.TopTapEnabledPoses is { Count: > 0 })
                _topTapEnabledPoses = new HashSet<TopTapPose>(dto.TopTapEnabledPoses);
            _petSpecies = dto.PetSpecies;
            _perchPreference = dto.PerchPreference;
            _tennisSpeed = dto.TennisSpeed;
            _tennisDifficulty = dto.TennisDifficulty;
            _suppressSave = false;
        }
        catch
        {
            _suppressSave = false;
        }
    }

    private void NotifyAndSave()
    {
        if (_suppressSave) return;
        Save();
        Changed?.Invoke();
    }

    private void Save()
    {
        if (string.IsNullOrWhiteSpace(_storagePath)) return;
        try
        {
            string? dir = Path.GetDirectoryName(_storagePath);
            if (!string.IsNullOrWhiteSpace(dir)) Directory.CreateDirectory(dir);
            var dto = new PersistedDto
            {
                WindowSwitchDelaySeconds = _windowSwitchDelaySeconds,
                ClimbToTopEnabled = _climbToTopEnabled,
                ClimbToTopIntervalSeconds = _climbToTopIntervalSeconds,
                TopEffectsEnabled = _topEffectsEnabled,
                TopEffectIntervalSeconds = _topEffectIntervalSeconds,
                EnabledTopEffects = OrderedEnabledTopEffects.ToList(),
                ShyRetreatEnabled = _shyRetreatEnabled,
                TypingPauseEnabled = _typingPauseEnabled,
                ClimbPawsPeekEnabled = _climbPawsPeekEnabled,
                DogScale = _dogScale,
                TopTapEnabledPoses = OrderedEnabledTopTapPoses.ToList(),
                PetSpecies = _petSpecies,
                PerchPreference = _perchPreference,
                TennisSpeed = _tennisSpeed,
                TennisDifficulty = _tennisDifficulty
            };
            File.WriteAllText(_storagePath, JsonSerializer.Serialize(dto, JsonOptions));
        }
        catch
        {
            // Ignore IO issues in read-only sandboxes
        }
    }
}
