using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using WestieDeskPet.Core;

namespace WestieDeskPet.Windows.Native;

public readonly record struct MonitorGeometry(
    IntPtr Handle,
    Win32Api.RECT PhysicalMonitor,
    Win32Api.RECT PhysicalWork,
    double DpiScaleX,
    double DpiScaleY)
{
    public double LeftDip => PhysicalMonitor.Left / DpiScaleX;
    public double TopDip => PhysicalMonitor.Top / DpiScaleY;
    public double WidthDip => PhysicalMonitor.Width / DpiScaleX;
    public double HeightDip => PhysicalMonitor.Height / DpiScaleY;
    public Size2D SizeDip => new(WidthDip, HeightDip);

    /// <summary>Converts a Windows physical top-left RECT into monitor-local bottom-left logical DIPs.</summary>
    public Rect2D ToLocalBottomLeftDip(Win32Api.RECT phys)
    {
        double x = (phys.Left - PhysicalMonitor.Left) / DpiScaleX;
        double y = (PhysicalMonitor.Bottom - phys.Bottom) / DpiScaleY;
        double w = phys.Width / DpiScaleX;
        double h = phys.Height / DpiScaleY;
        return new Rect2D(x, y, w, h);
    }

    public Vec2 CursorPhysicalToLocalBottomLeftDip(Win32Api.POINT pt)
    {
        double x = (pt.X - PhysicalMonitor.Left) / DpiScaleX;
        double y = (PhysicalMonitor.Bottom - pt.Y) / DpiScaleY;
        return new Vec2(x, y);
    }

    public Rect2D LocalVisibleWorkDip => ToLocalBottomLeftDip(PhysicalWork);
}

/// <summary>
/// Zero-permission Win32 active-window, Z-order occlusion, multi-monitor DPI, and typing-idle tracker.
/// </summary>
public sealed class WindowsPlatformTracker
{
    private static readonly string[] MeetingKeywords =
    [
        "zoom", "teams", "ms-teams", "webex", "lark", "feishu", "wemeet", "voov", "dingtalk"
    ];

    private static readonly string[] CodingKeywords =
    [
        "code", "cursor", "devenv", "rider", "pycharm", "idea", "windowsterminal", "wt", "wezterm", "alacritty", "zed", "copilot"
    ];

    private static readonly HashSet<string> IgnoredShellClasses = new(StringComparer.OrdinalIgnoreCase)
    {
        "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd",
        "Windows.UI.Core.CoreWindow", "ApplicationFrameWindow"
    };

    private readonly int _ownPid;
    private readonly Dictionary<uint, string> _procNameCache = new();
    private Win32Api.POINT _lastObservedCursor;
    private uint _lastObservedInputTick;
    private double _lastNonMouseInputSecondsAgo = 999.0;

    public WindowsPlatformTracker(int? ownPid = null)
    {
        _ownPid = ownPid ?? Environment.ProcessId;
    }

    public static MonitorGeometry GetActiveMonitorForCursor()
    {
        Win32Api.GetCursorPos(out var pt);
        IntPtr hMon = Win32Api.MonitorFromPoint(pt, Win32Api.MONITOR_DEFAULTTONEAREST);
        return QueryMonitorGeometry(hMon);
    }

    public static MonitorGeometry GetMonitorForForegroundOrCursor()
    {
        IntPtr fg = Win32Api.GetForegroundWindow();
        if (fg != IntPtr.Zero)
        {
            IntPtr hMon = Win32Api.MonitorFromWindow(fg, Win32Api.MONITOR_DEFAULTTONEAREST);
            if (hMon != IntPtr.Zero) return QueryMonitorGeometry(hMon);
        }
        return GetActiveMonitorForCursor();
    }

    public static MonitorGeometry QueryMonitorGeometry(IntPtr hMonitor)
    {
        var info = new Win32Api.MONITORINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Win32Api.MONITORINFO>() };
        Win32Api.GetMonitorInfo(hMonitor, ref info);
        var (sx, sy) = Win32Api.GetMonitorDpiScale(hMonitor);
        return new MonitorGeometry(hMonitor, info.rcMonitor, info.rcWork, sx, sy);
    }

    public ActiveWorkspaceSnapshot CaptureSnapshot(MonitorGeometry monitor)
    {
        IntPtr fgHwnd = Win32Api.GetForegroundWindow();
        uint fgPid = 0;
        if (fgHwnd != IntPtr.Zero)
            Win32Api.GetWindowThreadProcessId(fgHwnd, out fgPid);

        string frontName = fgPid != 0 ? ResolveProcessName(fgPid) : "";
        string lowered = frontName.ToLowerInvariant();
        bool isMeeting = MeetingKeywords.Any(k => lowered.Contains(k, StringComparison.Ordinal));
        bool isCoding = CodingKeywords.Any(k => lowered.Contains(k, StringComparison.Ordinal));

        var localVisible = monitor.LocalVisibleWorkDip;
        var monitorLocalRect = new Rect2D(0, 0, monitor.WidthDip, monitor.HeightDip);

        var parsed = new List<RawWindowInfo>(32);
        var framesById = new Dictionary<ulong, Rect2D>(32);
        var classBuf = new StringBuilder(128);

        Win32Api.EnumWindows((hwnd, _) =>
        {
            if (!Win32Api.IsWindowVisible(hwnd) || Win32Api.IsIconic(hwnd) || Win32Api.IsWindowCloaked(hwnd))
                return true;

            Win32Api.GetWindowThreadProcessId(hwnd, out uint pid);
            if ((int)pid == _ownPid) return true;

            long exStyle = Win32Api.GetWindowLongPtr(hwnd, Win32Api.GWL_EXSTYLE);
            if ((exStyle & Win32Api.WS_EX_TOOLWINDOW) != 0) return true;

            classBuf.Clear();
            Win32Api.GetClassName(hwnd, classBuf, classBuf.Capacity);
            string cls = classBuf.ToString();
            if (cls is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd")
                return true;

            if (!Win32Api.TryGetVisibleWindowBounds(hwnd, out var physRect))
                return true;

            var localRect = monitor.ToLocalBottomLeftDip(physRect);
            if (!localRect.Intersects(monitorLocalRect))
                return true;

            ulong wid = (ulong)hwnd.ToInt64();
            string owner = ResolveProcessName(pid);
            bool isFront = hwnd == fgHwnd || (fgPid != 0 && pid == fgPid);

            parsed.Add(new RawWindowInfo(wid, (int)pid, owner, localRect, IsFrontmostApp: isFront));
            framesById[wid] = localRect;
            return true;
        }, IntPtr.Zero);

        var platforms = PlatformPhysics.ExtractVisiblePlatforms(parsed, localVisible, _ownPid);
        var perchLayout = PlatformPhysics.ComputeActiveWindowPerchLayout(parsed, monitor.SizeDip, localVisible, _ownPid);
        double secsSinceTyping = QuerySecondsSinceLikelyTyping();

        return new ActiveWorkspaceSnapshot(
            platforms, perchLayout, parsed, framesById,
            monitor.SizeDip, localVisible, frontName,
            isMeeting, isCoding, secsSinceTyping);
    }

    /// <summary>
    /// Ultra-lightweight O(1) per-frame refresh for active & anchored windows (zero-lag window drag follow!).
    /// </summary>
    public ActiveWorkspaceSnapshot FastRefreshActiveWindow(
        ActiveWorkspaceSnapshot previous,
        MonitorGeometry monitor,
        ulong trackedWindowId)
    {
        var updatedLayout = previous.PerchLayout;
        var updatedFrames = new Dictionary<ulong, Rect2D>(previous.WindowFramesById);
        var updatedWindows = previous.WindowsFrontToBack.ToList();
        var localVisible = monitor.LocalVisibleWorkDip;
        bool changed = false;

        bool TryRefresh(ulong winId, out Rect2D localRect)
        {
            localRect = Rect2D.Empty;
            if (winId == 0) return false;
            var hwnd = new IntPtr(unchecked((long)winId));
            if (!Win32Api.IsWindowVisible(hwnd) || Win32Api.IsIconic(hwnd)) return false;
            if (!Win32Api.TryGetVisibleWindowBounds(hwnd, out var phys)) return false;
            localRect = monitor.ToLocalBottomLeftDip(phys);
            return true;
        }

        if (previous.PerchLayout.ActiveWindowId is { } activeId && activeId != 0 && TryRefresh(activeId, out var activeRect))
        {
            var old = previous.PerchLayout.ActiveWindowFrame;
            bool moved = old is null
                || Math.Abs(old.Value.X - activeRect.X) >= 0.05
                || Math.Abs(old.Value.Y - activeRect.Y) >= 0.05
                || Math.Abs(old.Value.Width - activeRect.Width) >= 0.05
                || Math.Abs(old.Value.Height - activeRect.Height) >= 0.05;

            if (moved)
            {
                changed = true;
                updatedFrames[activeId] = activeRect;
                updatedLayout = PlatformPhysics.ComputeSingleWindowPerchLayout(
                    activeId, previous.FrontmostAppName, activeRect, monitor.SizeDip, localVisible);
                int idx = updatedWindows.FindIndex(w => w.WindowId == activeId);
                if (idx >= 0)
                    updatedWindows[idx] = updatedWindows[idx] with { Frame = activeRect };
            }
        }

        if (trackedWindowId != 0 && trackedWindowId != previous.PerchLayout.ActiveWindowId &&
            TryRefresh(trackedWindowId, out var trackedRect))
        {
            if (!previous.WindowFramesById.TryGetValue(trackedWindowId, out var old) ||
                Math.Abs(old.X - trackedRect.X) >= 0.05 || Math.Abs(old.Y - trackedRect.Y) >= 0.05 ||
                Math.Abs(old.Width - trackedRect.Width) >= 0.05 || Math.Abs(old.Height - trackedRect.Height) >= 0.05)
            {
                changed = true;
                updatedFrames[trackedWindowId] = trackedRect;
            }
        }

        double secsSinceTyping = QuerySecondsSinceLikelyTyping();
        if (!changed && Math.Abs(secsSinceTyping - previous.SecondsSinceLastKeyDown) < 0.2)
            return previous;

        return new ActiveWorkspaceSnapshot(
            previous.Platforms, updatedLayout, updatedWindows, updatedFrames,
            monitor.SizeDip, localVisible, previous.FrontmostAppName,
            previous.IsMeetingActive, previous.IsCodingActive, secsSinceTyping);
    }

    /// <summary>
    /// Zero-permission typing idle heuristic via `GetLastInputInfo`:
    /// ignores pure mouse movement so typing pauses climb-to-top while gentle mouse browsing doesn't!
    /// </summary>
    private double QuerySecondsSinceLikelyTyping()
    {
        var lii = new Win32Api.LASTINPUTINFO { cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<Win32Api.LASTINPUTINFO>() };
        if (!Win32Api.GetLastInputInfo(ref lii))
            return 999.0;

        Win32Api.GetCursorPos(out var curPt);
        bool cursorMoved = curPt.X != _lastObservedCursor.X || curPt.Y != _lastObservedCursor.Y;
        _lastObservedCursor = curPt;

        uint nowTick = unchecked((uint)Environment.TickCount);
        double idleSec = unchecked(nowTick - lii.dwTime) / 1000.0;

        if (lii.dwTime != _lastObservedInputTick)
        {
            _lastObservedInputTick = lii.dwTime;
            if (!cursorMoved)
            {
                // Input tick advanced while cursor stayed stationary -> keyboard input!
                _lastNonMouseInputSecondsAgo = 0.0;
                return 0.0;
            }
        }

        _lastNonMouseInputSecondsAgo = Math.Max(idleSec, _lastNonMouseInputSecondsAgo + 0.016);
        return _lastNonMouseInputSecondsAgo;
    }

    private string ResolveProcessName(uint pid)
    {
        if (_procNameCache.TryGetValue(pid, out string? cached)) return cached;
        string name = "Window";
        try
        {
            using var p = Process.GetProcessById((int)pid);
            name = p.ProcessName;
        }
        catch
        {
            // Elevated or exited process
        }
        if (_procNameCache.Count > 256) _procNameCache.Clear();
        _procNameCache[pid] = name;
        return name;
    }
}
