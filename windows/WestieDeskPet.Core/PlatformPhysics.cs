using System;
using System.Collections.Generic;
using System.Linq;

namespace WestieDeskPet.Core;

public sealed record RawWindowInfo(
    ulong WindowId,
    int OwnerPid,
    string OwnerName,
    Rect2D Frame,
    bool IsFrontmostApp = false,
    int Layer = 0,
    double Alpha = 1.0);

public sealed record WindowPlatform(
    ulong WindowId,
    string OwnerName,
    double MinX,
    double MaxX,
    double Y,
    double WindowMinX,
    bool IsDockFloor,
    bool IsFrontmost)
{
    public string Id => $"{WindowId}-{(int)Math.Round(MinX)}-{(int)Math.Round(Y)}";
    public double Width => Math.Max(0, MaxX - MinX);
    public double MidX => (MinX + MaxX) * 0.5;

    public bool ContainsX(double x, double margin = 10) => x >= (MinX + margin) && x <= (MaxX - margin);

    public double ClampedX(double x, double margin = 18)
    {
        if (MaxX - MinX <= margin * 2) return MidX;
        return Math.Clamp(x, MinX + margin, MaxX - margin);
    }
}

public sealed record RightEdgeAnchor(double EdgeX, double MinY, double MaxY, double DefaultY)
{
    public double ClampedY(double y) => MaxY > MinY ? Math.Clamp(y, MinY, MaxY) : DefaultY;
}

public sealed record ActiveWindowPerchLayout(
    ulong? ActiveWindowId,
    Rect2D? ActiveWindowFrame,
    bool IsFullScreenMode,
    WindowPlatform? TopPerch,
    RightEdgeAnchor? WindowRightPeek,
    RightEdgeAnchor ScreenRightPeek);

public sealed class ActiveWorkspaceSnapshot
{
    public IReadOnlyList<WindowPlatform> Platforms { get; }
    public ActiveWindowPerchLayout PerchLayout { get; }
    public IReadOnlyList<RawWindowInfo> WindowsFrontToBack { get; }
    public IReadOnlyDictionary<ulong, Rect2D> WindowFramesById { get; }
    public Size2D ScreenSize { get; }
    public Rect2D VisibleScreenFrame { get; }
    public string FrontmostAppName { get; }
    public bool IsMeetingActive { get; }
    public bool IsCodingActive { get; }
    public double SecondsSinceLastKeyDown { get; }

    public ActiveWorkspaceSnapshot(
        IReadOnlyList<WindowPlatform> platforms,
        ActiveWindowPerchLayout perchLayout,
        IReadOnlyList<RawWindowInfo> windowsFrontToBack,
        IReadOnlyDictionary<ulong, Rect2D> windowFramesById,
        Size2D screenSize,
        Rect2D visibleScreenFrame,
        string frontmostAppName,
        bool isMeetingActive,
        bool isCodingActive,
        double secondsSinceLastKeyDown = 999.0)
    {
        Platforms = platforms;
        PerchLayout = perchLayout;
        WindowsFrontToBack = windowsFrontToBack;
        WindowFramesById = windowFramesById;
        ScreenSize = screenSize;
        VisibleScreenFrame = visibleScreenFrame;
        FrontmostAppName = frontmostAppName;
        IsMeetingActive = isMeetingActive;
        IsCodingActive = isCodingActive;
        SecondsSinceLastKeyDown = secondsSinceLastKeyDown;
    }

    public ActiveWindowPerchLayout? GetPerchLayoutForWindow(ulong windowId)
    {
        if (PerchLayout.ActiveWindowId == windowId)
            return PerchLayout;
        if (!WindowFramesById.TryGetValue(windowId, out Rect2D frame))
            return null;
        string ownerName = WindowsFrontToBack.FirstOrDefault(w => w.WindowId == windowId)?.OwnerName ?? "Window";
        return PlatformPhysics.ComputeSingleWindowPerchLayout(
            windowId, ownerName, frame, ScreenSize, VisibleScreenFrame);
    }
}

public static class PlatformPhysics
{
    public const double MinSegmentWidth = 76.0;
    public const double HeadClearance = 38.0;

    public static List<WindowPlatform> ExtractVisiblePlatforms(
        IReadOnlyList<RawWindowInfo> windowsFrontToBack,
        Rect2D visibleScreenFrame,
        int excludedPid)
    {
        var occluders = new List<Rect2D>();
        var platforms = new List<WindowPlatform>();

        double maxAllowedTopY = visibleScreenFrame.MaxY - HeadClearance;
        double minAllowedTopY = visibleScreenFrame.MinY + 24;

        foreach (var win in windowsFrontToBack)
        {
            if (win.OwnerPid == excludedPid || win.Layer != 0 || win.Alpha < 0.2 ||
                win.Frame.Width < 140 || win.Frame.Height < 70)
                continue;

            double clippedMinX = Math.Max(win.Frame.MinX, visibleScreenFrame.MinX + 6);
            double clippedMaxX = Math.Min(win.Frame.MaxX, visibleScreenFrame.MaxX - 6);
            double topY = win.Frame.MaxY;

            if (topY <= maxAllowedTopY && topY >= minAllowedTopY && clippedMaxX - clippedMinX >= MinSegmentWidth)
            {
                double probeY = topY + 6;
                var intervals = new List<(double A, double B)> { (clippedMinX + 8, clippedMaxX - 8) };

                foreach (var occ in occluders)
                {
                    if (probeY >= occ.MinY && probeY <= occ.MaxY + 18)
                    {
                        intervals = SubtractInterval(intervals, occ.MinX - 6, occ.MaxX + 6);
                        if (intervals.Count == 0) break;
                    }
                }

                foreach (var (segMin, segMax) in intervals)
                {
                    if (segMax - segMin >= MinSegmentWidth)
                    {
                        platforms.Add(new WindowPlatform(
                            win.WindowId, win.OwnerName, segMin, segMax, topY,
                            win.Frame.MinX, false, win.IsFrontmostApp));
                    }
                }
            }

            occluders.Add(win.Frame);
        }

        platforms.Add(new WindowPlatform(
            0, "Taskbar",
            visibleScreenFrame.MinX + 24,
            visibleScreenFrame.MaxX - 24,
            Math.Max(visibleScreenFrame.MinY, 4),
            visibleScreenFrame.MinX,
            true, false));

        platforms.Sort((lhs, rhs) =>
            Math.Abs(lhs.Y - rhs.Y) > 0.5 ? rhs.Y.CompareTo(lhs.Y) : lhs.MinX.CompareTo(rhs.MinX));
        return platforms;
    }

    public static List<(double A, double B)> SubtractInterval(
        IReadOnlyList<(double A, double B)> intervals,
        double cutMin,
        double cutMax)
    {
        if (cutMax <= cutMin) return intervals.ToList();
        var result = new List<(double, double)>(intervals.Count);
        foreach (var (a, b) in intervals)
        {
            if (cutMax <= a || cutMin >= b)
            {
                result.Add((a, b));
            }
            else
            {
                if (cutMin > a) result.Add((a, cutMin));
                if (cutMax < b) result.Add((cutMax, b));
            }
        }
        return result;
    }

    public static ActiveWindowPerchLayout ComputeSingleWindowPerchLayout(
        ulong windowId,
        string ownerName,
        Rect2D windowFrame,
        Size2D screenSize,
        Rect2D visibleScreenFrame)
    {
        var raw = new RawWindowInfo(windowId, 0, ownerName, windowFrame, IsFrontmostApp: true);
        return ComputeActiveWindowPerchLayout([raw], screenSize, visibleScreenFrame, excludedPid: -1);
    }

    /// <summary>
    /// Computes active-window perches. Note on Windows, window min/max/close buttons sit on the TOP-RIGHT (~136pt),
    /// so `topPerch` leaves comfortable clearance on the right while avoiding the left icon!
    /// </summary>
    public static ActiveWindowPerchLayout ComputeActiveWindowPerchLayout(
        IReadOnlyList<RawWindowInfo> windowsFrontToBack,
        Size2D screenSize,
        Rect2D visibleScreenFrame,
        int excludedPid)
    {
        var screenRight = new RightEdgeAnchor(
            EdgeX: screenSize.Width,
            MinY: Math.Max(visibleScreenFrame.MinY + 90, 110),
            MaxY: Math.Max(visibleScreenFrame.MinY + 120, screenSize.Height - 90),
            DefaultY: Math.Clamp(screenSize.Height * 0.66, 160, Math.Max(160, screenSize.Height - 110)));

        var standardWindows = windowsFrontToBack
            .Where(w => w.OwnerPid != excludedPid && w.Layer == 0 && w.Alpha >= 0.2 &&
                        w.Frame.Width >= 200 && w.Frame.Height >= 120)
            .ToList();

        var activeWin = standardWindows.FirstOrDefault(w => w.IsFrontmostApp) ?? standardWindows.FirstOrDefault();
        if (activeWin is null)
        {
            return new ActiveWindowPerchLayout(null, null, true, null, null, screenRight);
        }

        Rect2D f = activeWin.Frame;
        double topHeadroom = visibleScreenFrame.MaxY - f.MaxY;
        double physicalTopClearance = screenSize.Height - f.MaxY;
        double rightHeadroom = screenSize.Width - f.MaxX;

        bool coversScreen = f.Width >= screenSize.Width - 24 && f.Height >= visibleScreenFrame.Height - 24;
        bool hasTopRoom = topHeadroom >= 20 || (topHeadroom >= 4 && physicalTopClearance >= 40);
        bool hasRightRoom = rightHeadroom >= 36 && f.MaxX >= 120;

        if (coversScreen || (!hasTopRoom && !hasRightRoom))
        {
            return new ActiveWindowPerchLayout(activeWin.WindowId, f, true, null, null, screenRight);
        }

        WindowPlatform? topPlatform = null;
        if (hasTopRoom)
        {
            // Keep clear of top-left window icon (~36pt) and Windows top-right min/max/close buttons (~118pt)
            double safeMinX = Math.Max(f.MinX + 36, visibleScreenFrame.MinX + 20);
            double safeMaxX = Math.Min(f.MaxX - 24, screenSize.Width - 24);
            if (safeMaxX - safeMinX >= 70)
            {
                topPlatform = new WindowPlatform(
                    activeWin.WindowId, activeWin.OwnerName, safeMinX, safeMaxX, f.MaxY,
                    f.MinX, false, true);
            }
        }

        RightEdgeAnchor? rightPeek = null;
        if (hasRightRoom)
        {
            double maxY = Math.Min(f.MaxY - 46, visibleScreenFrame.MaxY - 46);
            double minY = Math.Max(f.MinY + 52, visibleScreenFrame.MinY + 52);
            if (maxY >= minY)
            {
                double defaultY = Math.Clamp(f.MaxY - 88, minY, maxY);
                rightPeek = new RightEdgeAnchor(f.MaxX, minY, maxY, defaultY);
            }
        }

        bool fallbackFullScreen = topPlatform is null && rightPeek is null;
        return new ActiveWindowPerchLayout(activeWin.WindowId, f, fallbackFullScreen, topPlatform, rightPeek, screenRight);
    }

    public static bool IsRectOccludedByFrontWindows(
        Rect2D rect,
        ulong ownerWindowId,
        IReadOnlyList<RawWindowInfo> windowsFrontToBack,
        int excludedPid)
    {
        foreach (var win in windowsFrontToBack)
        {
            if (win.OwnerPid == excludedPid || win.Layer != 0 || win.Alpha < 0.2 ||
                win.Frame.Width < 120 || win.Frame.Height < 70)
                continue;

            if (win.WindowId == ownerWindowId)
                return false;

            Rect2D inter = win.Frame.Intersect(rect);
            if (!inter.IsEmpty && inter.Width >= 10 && inter.Height >= 10)
                return true;
        }
        return false;
    }
}
