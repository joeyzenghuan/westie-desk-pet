using System;
using System.Linq;
using System.Threading;
using System.Windows;
using WestieDeskPet.Core;
using WestieDeskPet.Windows.Rendering;
using WestieDeskPet.Windows.UI;

namespace WestieDeskPet.Windows;

public partial class App : System.Windows.Application
{
    private Mutex? _singleInstanceMutex;
    private OverlayWindow? _overlayWindow;
    private TrayController? _trayController;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _singleInstanceMutex = new Mutex(true, "Local\\WestieDeskPet.Windows.SingleInstance", out bool createdNew);
        if (!createdNew)
        {
            Shutdown();
            return;
        }

        bool startTennis = e.Args.Any(a => a.Equals("--tennis", StringComparison.OrdinalIgnoreCase));

        _overlayWindow = new OverlayWindow(CompanionPreferences.Shared);
        _overlayWindow.Show();
        _trayController = new TrayController(_overlayWindow);

        if (startTennis)
        {
            _overlayWindow.SwitchToMode(AppInteractionMode.Tennis);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayController?.Dispose();
        _overlayWindow?.Close();
        _singleInstanceMutex?.Dispose();
        base.OnExit(e);
    }
}
