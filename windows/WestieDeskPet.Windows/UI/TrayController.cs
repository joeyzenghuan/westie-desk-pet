using System;
using System.Drawing;
using System.Windows.Forms;
using WestieDeskPet.Core;
using WestieDeskPet.Windows.Rendering;

namespace WestieDeskPet.Windows.UI;

public sealed class TrayController : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly OverlayWindow _overlay;
    private Icon? _currentIcon;

    public TrayController(OverlayWindow overlay)
    {
        _overlay = overlay;
        _notifyIcon = new NotifyIcon
        {
            Visible = true,
            Text = "Westie Desk Pet — 桌面宠物 & 网球"
        };
        _notifyIcon.DoubleClick += (_, _) => _overlay.Dispatcher.Invoke(() => _overlay.OpenPreferences());

        _overlay.Preferences.Changed += OnPreferencesChanged;
        _overlay.ModeChanged += OnModeChanged;

        RefreshTrayIconAndMenu();
    }

    private void OnPreferencesChanged() =>
        _overlay.Dispatcher.BeginInvoke(RefreshTrayIconAndMenu);

    private void OnModeChanged(AppInteractionMode _) =>
        _overlay.Dispatcher.BeginInvoke(RefreshTrayIconAndMenu);

    public void RefreshTrayIconAndMenu()
    {
        var prefs = _overlay.Preferences;
        var sp = prefs.PetSpecies;

        var nextIcon = WpfSpriteBank.Shared.CreateTrayIcon(sp);
        if (nextIcon is not null)
        {
            var old = _currentIcon;
            _currentIcon = nextIcon;
            _notifyIcon.Icon = nextIcon;
            old?.Dispose();
        }
        else if (_notifyIcon.Icon is null)
        {
            _notifyIcon.Icon = SystemIcons.Application;
        }

        _notifyIcon.Text = $"Westie Desk Pet — {sp.DisplayName()}陪伴 & 网球";

        var oldMenu = _notifyIcon.ContextMenuStrip;
        _notifyIcon.ContextMenuStrip = BuildTrayMenu();
        oldMenu?.Dispose();
    }

    private ContextMenuStrip BuildTrayMenu()
    {
        var prefs = _overlay.Preferences;
        var sp = prefs.PetSpecies;
        var menu = new ContextMenuStrip();

        var header = new ToolStripMenuItem($"{sp.DisplayName()} · 桌面伙伴")
        {
            Enabled = false
        };
        menu.Items.Add(header);
        menu.Items.Add(new ToolStripSeparator());

        // 1. Most-used: Playable Top-Bar Effects right on Level 1!
        menu.Items.Add("👀 探头张望", null, (_, _) => _overlay.PreviewClimbPeekOnTop());
        foreach (var eff in Enum.GetValues<TopBarEffect>())
        {
            var e = eff;
            menu.Items.Add(e.DisplayName(), null, (_, _) => _overlay.PlayTopBarEffect(e));
        }

        menu.Items.Add(new ToolStripSeparator());

        // 2. Feed Snack & Quiet Sleep right after effects!
        string snackTitle = sp.IsCat() ? "🐟 投喂一条小鱼干" : "🦴 投喂一根骨头饼干";
        menu.Items.Add(snackTitle, null, (_, _) => _overlay.FeedSnack());

        var sleepItem = new ToolStripMenuItem(_overlay.ForceQuietSleep ? "☀️ 取消固定趴睡" : "💤 安静趴睡模式",
            null, (_, _) => _overlay.ToggleQuietSleep())
        {
            Checked = _overlay.ForceQuietSleep
        };
        menu.Items.Add(sleepItem);

        menu.Items.Add(new ToolStripSeparator());

        // 3. Tennis + Speed + Difficulty grouped together!
        string tennisTitle = _overlay.Mode == AppInteractionMode.Tennis
            ? "🏡 收起球场回到桌面陪伴"
            : "🎾 开始打网球 (WASD + 鼠标)";
        menu.Items.Add(tennisTitle, null, (_, _) => _overlay.ToggleTennisMode());
        menu.Items.Add($"🟢 让{sp.ShortName()}叼网球过来", null, (_, _) => _overlay.TriggerTennisInvite());

        var speedMenu = new ToolStripMenuItem($"⏱ 网球球速: {prefs.TennisSpeed.ShortName()}");
        foreach (var spd in Enum.GetValues<TennisGameSpeed>())
        {
            var s = spd;
            string suffix = s == TennisGameSpeed.Slow ? " (默认)" : "";
            speedMenu.DropDownItems.Add(new ToolStripMenuItem($"{s.DisplayName()}{suffix}", null, (_, _) => prefs.TennisSpeed = s)
            {
                Checked = s == prefs.TennisSpeed
            });
        }
        menu.Items.Add(speedMenu);

        var diffMenu = new ToolStripMenuItem("🏆 网球对手难度");
        foreach (var diff in Enum.GetValues<TennisDifficulty>())
        {
            var d = diff;
            diffMenu.DropDownItems.Add(new ToolStripMenuItem($"{d.DisplayName(sp)} ({d})", null, (_, _) => prefs.TennisDifficulty = d)
            {
                Checked = d == prefs.TennisDifficulty
            });
        }
        menu.Items.Add(diffMenu);

        menu.Items.Add(new ToolStripSeparator());

        // 4. Quick Position Move
        menu.Items.Add("📍 移到当前窗口正上方", null, (_, _) => _overlay.MoveToZone(PerchZone.WindowTop));
        menu.Items.Add("👀 移到屏幕右侧边", null, (_, _) => _overlay.MoveToRightEdge());

        menu.Items.Add(new ToolStripSeparator());

        // 5. Pet Species Switch in its own standalone section!
        var speciesMenu = new ToolStripMenuItem($"🎭 切换宠物: {sp.ShortName()}");
        foreach (var candidate in Enum.GetValues<PetSpecies>())
        {
            var c = candidate;
            var item = new ToolStripMenuItem(c.DisplayName(), null, (_, _) => prefs.PetSpecies = c)
            {
                Checked = c == sp
            };
            speciesMenu.DropDownItems.Add(item);
        }
        menu.Items.Add(speciesMenu);

        menu.Items.Add(new ToolStripSeparator());

        // 5. All Settings grouped cleanly under Level-2 Submenu!
        var settingsMenu = new ToolStripMenuItem("⚙️ 设置");

        var perchMenu = new ToolStripMenuItem("🧭 陪伴位置偏好");
        foreach (var pp in Enum.GetValues<PerchPreference>())
        {
            var p = pp;
            var item = new ToolStripMenuItem(p.DisplayName(), null, (_, _) =>
            {
                prefs.PerchPreference = p;
                _overlay.SummonToActiveWindow();
            })
            {
                Checked = p == prefs.PerchPreference
            };
            perchMenu.DropDownItems.Add(item);
        }
        settingsMenu.DropDownItems.Add(perchMenu);

        var delayMenu = new ToolStripMenuItem($"🕵️ 换窗等待: {CompanionPreferences.FormatDuration(prefs.WindowSwitchDelaySeconds)}");
        foreach (var (title, secs) in CompanionPreferences.SwitchDelayPresets)
        {
            double s = secs;
            delayMenu.DropDownItems.Add(new ToolStripMenuItem(title, null, (_, _) => prefs.WindowSwitchDelaySeconds = s)
            {
                Checked = Math.Abs(prefs.WindowSwitchDelaySeconds - s) < 0.1
            });
        }
        settingsMenu.DropDownItems.Add(delayMenu);

        string climbLabel = prefs.ClimbToTopEnabled ? CompanionPreferences.FormatDuration(prefs.ClimbToTopIntervalSeconds) : "已关闭";
        var climbMenu = new ToolStripMenuItem($"🐾 爬顶等待: {climbLabel}");
        foreach (var (title, enabled, secs) in CompanionPreferences.ClimbIntervalPresets)
        {
            bool en = enabled;
            double s = secs;
            bool selected = en ? (prefs.ClimbToTopEnabled && Math.Abs(prefs.ClimbToTopIntervalSeconds - s) < 0.5) : !prefs.ClimbToTopEnabled;
            climbMenu.DropDownItems.Add(new ToolStripMenuItem(title, null, (_, _) =>
            {
                prefs.ClimbToTopEnabled = en;
                if (en) prefs.ClimbToTopIntervalSeconds = s;
            })
            {
                Checked = selected
            });
        }
        settingsMenu.DropDownItems.Add(climbMenu);

        string effectLabel = prefs.TopEffectsEnabled ? CompanionPreferences.FormatDuration(prefs.TopEffectIntervalSeconds) : "已关闭";
        var effectMenu = new ToolStripMenuItem($"✨ 特效间隔: {effectLabel}");
        foreach (var (title, enabled, secs) in CompanionPreferences.EffectIntervalPresets)
        {
            bool en = enabled;
            double s = secs;
            bool selected = en ? (prefs.TopEffectsEnabled && Math.Abs(prefs.TopEffectIntervalSeconds - s) < 0.5) : !prefs.TopEffectsEnabled;
            effectMenu.DropDownItems.Add(new ToolStripMenuItem(title, null, (_, _) =>
            {
                prefs.TopEffectsEnabled = en;
                if (en) prefs.TopEffectIntervalSeconds = s;
            })
            {
                Checked = selected
            });
        }
        settingsMenu.DropDownItems.Add(effectMenu);

        var scaleMenu = new ToolStripMenuItem($"📏 宠物大小: {CompanionPreferences.FormatScale(prefs.DogScale)}");
        foreach (var (title, scale) in CompanionPreferences.DogScalePresets)
        {
            double sc = scale;
            scaleMenu.DropDownItems.Add(new ToolStripMenuItem(title, null, (_, _) => prefs.DogScale = sc)
            {
                Checked = Math.Abs(prefs.DogScale - sc) < 0.03
            });
        }
        settingsMenu.DropDownItems.Add(scaleMenu);

        settingsMenu.DropDownItems.Add(new ToolStripSeparator());
        settingsMenu.DropDownItems.Add("⚙️ 陪伴偏好设置…", null, (_, _) => _overlay.OpenPreferences());
        menu.Items.Add(settingsMenu);

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("退出 Westie Desk Pet", null, (_, _) => System.Windows.Application.Current.Shutdown());

        return menu;
    }

    public void Dispose()
    {
        _overlay.Preferences.Changed -= OnPreferencesChanged;
        _overlay.ModeChanged -= OnModeChanged;
        _notifyIcon.Visible = false;
        _notifyIcon.ContextMenuStrip?.Dispose();
        _notifyIcon.Dispose();
        _currentIcon?.Dispose();
    }
}
