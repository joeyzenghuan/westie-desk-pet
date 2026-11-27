using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Media.Imaging;
using WestieDeskPet.Core;
using WestieDeskPet.Windows.Native;

namespace WestieDeskPet.Windows.Rendering;

public sealed class WpfSpriteBank
{
    public static WpfSpriteBank Shared { get; } = new();

    private readonly Dictionary<string, BitmapImage> _cache = new(StringComparer.OrdinalIgnoreCase);
    private readonly string _spritesDir;

    private WpfSpriteBank()
    {
        _spritesDir = Path.Combine(AppContext.BaseDirectory, "Sprites");
    }

    public void PreloadSpecies(PetSpecies species)
    {
        foreach (var key in SpriteAssetCatalog.AllKeys)
            _ = GetImage(key, species);
    }

    public BitmapImage? GetImage(SpriteAssetKey key, PetSpecies species)
    {
        string name = SpriteAssetCatalog.GetResourceName(key, species);
        if (_cache.TryGetValue(name, out var cached)) return cached;

        string path = Path.Combine(_spritesDir, name + ".png");
        if (!File.Exists(path) && species != PetSpecies.Westie)
        {
            string fallbackName = SpriteAssetCatalog.GetBaseName(key);
            path = Path.Combine(_spritesDir, fallbackName + ".png");
        }
        if (!File.Exists(path)) return null;

        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.UriSource = new Uri(path, UriKind.Absolute);
            bmp.EndInit();
            bmp.Freeze();
            _cache[name] = bmp;
            return bmp;
        }
        catch
        {
            return null;
        }
    }

    public Icon? CreateTrayIcon(PetSpecies species)
    {
        string name = SpriteAssetCatalog.GetResourceName(SpriteAssetKey.BadgeIcon, species);
        string path = Path.Combine(_spritesDir, name + ".png");
        if (!File.Exists(path))
            path = Path.Combine(_spritesDir, "badge_icon.png");
        if (!File.Exists(path)) return null;

        try
        {
            using var src = new Bitmap(path);
            using var resized = new Bitmap(32, 32);
            using (var g = Graphics.FromImage(resized))
            {
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
                g.DrawImage(src, 0, 0, 32, 32);
            }
            IntPtr hIcon = resized.GetHicon();
            try
            {
                using var tempIcon = Icon.FromHandle(hIcon);
                return (Icon)tempIcon.Clone();
            }
            finally
            {
                Win32Api.DestroyIcon(hIcon);
            }
        }
        catch
        {
            return null;
        }
    }
}
