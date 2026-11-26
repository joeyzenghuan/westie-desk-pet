using System;

namespace WestieDeskPet.Core;

/// <summary>
/// 2D point / vector in monitor-local logical DIPs with bottom-left origin (matching macOS SpriteKit 1:1).
/// </summary>
public readonly record struct Vec2(double X, double Y)
{
    public static readonly Vec2 Zero = new(0, 0);

    public double Length => Math.Sqrt(X * X + Y * Y);
    public static double Distance(Vec2 a, Vec2 b) => Math.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y));
    public static double Hypot(double dx, double dy) => Math.Sqrt(dx * dx + dy * dy);
}

public readonly record struct Size2D(double Width, double Height)
{
    public static readonly Size2D Zero = new(0, 0);
}

/// <summary>
/// Axis-aligned rectangle in bottom-left origin logical DIP coordinates (`MinY` = bottom, `MaxY` = top).
/// </summary>
public readonly record struct Rect2D(double X, double Y, double Width, double Height)
{
    public static readonly Rect2D Empty = new(0, 0, 0, 0);

    public double MinX => X;
    public double MaxX => X + Width;
    public double MinY => Y;
    public double MaxY => Y + Height;
    public double MidX => X + Width * 0.5;
    public double MidY => Y + Height * 0.5;
    public bool IsEmpty => Width <= 0 || Height <= 0;

    public bool Contains(Vec2 pt) =>
        !IsEmpty && pt.X >= MinX && pt.X <= MaxX && pt.Y >= MinY && pt.Y <= MaxY;

    public Rect2D InsetBy(double dx, double dy)
    {
        if (IsEmpty) return Empty;
        double nw = Width - dx * 2;
        double nh = Height - dy * 2;
        if (nw <= 0 || nh <= 0) return Empty;
        return new Rect2D(X + dx, Y + dy, nw, nh);
    }

    public Rect2D Union(Rect2D other)
    {
        if (IsEmpty) return other;
        if (other.IsEmpty) return this;
        double x0 = Math.Min(MinX, other.MinX);
        double y0 = Math.Min(MinY, other.MinY);
        double x1 = Math.Max(MaxX, other.MaxX);
        double y1 = Math.Max(MaxY, other.MaxY);
        return new Rect2D(x0, y0, x1 - x0, y1 - y0);
    }

    public Rect2D Intersect(Rect2D other)
    {
        if (IsEmpty || other.IsEmpty) return Empty;
        double x0 = Math.Max(MinX, other.MinX);
        double y0 = Math.Max(MinY, other.MinY);
        double x1 = Math.Min(MaxX, other.MaxX);
        double y1 = Math.Min(MaxY, other.MaxY);
        if (x1 <= x0 || y1 <= y0) return Empty;
        return new Rect2D(x0, y0, x1 - x0, y1 - y0);
    }

    public bool Intersects(Rect2D other) => !Intersect(other).IsEmpty;
}
