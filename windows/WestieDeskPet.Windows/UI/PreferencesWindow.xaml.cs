using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using WestieDeskPet.Core;

namespace WestieDeskPet.Windows.UI;

public partial class PreferencesWindow : Window
{
    private readonly CompanionPreferences _prefs;
    private readonly Action _onPreviewPeek;
    private readonly Action<TopBarEffect> _onPlayEffect;
    private readonly Action _onPerchChanged;
    private bool _isLoading;

    public PreferencesWindow(
        CompanionPreferences prefs,
        Action onPreviewPeek,
        Action<TopBarEffect> onPlayEffect,
        Action onPerchChanged)
    {
        _prefs = prefs;
        _onPreviewPeek = onPreviewPeek;
        _onPlayEffect = onPlayEffect;
        _onPerchChanged = onPerchChanged;

        InitializeComponent();

        foreach (var pp in Enum.GetValues<PerchPreference>())
            PerchPreferenceCombo.Items.Add(new ComboBoxItem { Content = pp.DisplayName(), Tag = pp });

        SyncFromPreferences();
        _prefs.Changed += OnExternalPrefsChanged;
        Closed += (_, _) => _prefs.Changed -= OnExternalPrefsChanged;
    }

    private void OnExternalPrefsChanged() => Dispatcher.BeginInvoke(SyncFromPreferences);

    private void SyncFromPreferences()
    {
        _isLoading = true;
        try
        {
            WestieRadio.IsChecked = _prefs.PetSpecies == PetSpecies.Westie;
            CatRadio.IsChecked = _prefs.PetSpecies == PetSpecies.GoldenCat;
            LabradorRadio.IsChecked = _prefs.PetSpecies == PetSpecies.Labrador;
            ChinchillaRadio.IsChecked = _prefs.PetSpecies == PetSpecies.Chinchilla;

            ScaleSlider.Value = _prefs.DogScale;
            ScaleValueText.Text = CompanionPreferences.FormatScale(_prefs.DogScale);

            SwitchDelaySlider.Value = _prefs.WindowSwitchDelaySeconds;
            SwitchDelayText.Text = CompanionPreferences.FormatDuration(_prefs.WindowSwitchDelaySeconds);

            SelectComboTag(PerchPreferenceCombo, _prefs.PerchPreference);

            ClimbEnabledCheck.IsChecked = _prefs.ClimbToTopEnabled;
            ClimbIntervalSlider.Value = _prefs.ClimbToTopIntervalSeconds;
            ClimbIntervalText.Text = CompanionPreferences.FormatDuration(_prefs.ClimbToTopIntervalSeconds);
            ClimbIntervalSlider.IsEnabled = _prefs.ClimbToTopEnabled;

            TopEffectsEnabledCheck.IsChecked = _prefs.TopEffectsEnabled;
            EffectIntervalSlider.Value = _prefs.TopEffectIntervalSeconds;
            EffectIntervalText.Text = CompanionPreferences.FormatDuration(_prefs.TopEffectIntervalSeconds);
            EffectIntervalSlider.IsEnabled = _prefs.TopEffectsEnabled;

            EffectPatrolCheck.IsChecked = _prefs.IsTopEffectEnabled(TopBarEffect.Patrol);
            EffectFlashCheck.IsChecked = _prefs.IsTopEffectEnabled(TopBarEffect.FlashStep);
            EffectBearCheck.IsChecked = _prefs.IsTopEffectEnabled(TopBarEffect.BearShake);
            EffectKickCheck.IsChecked = _prefs.IsTopEffectEnabled(TopBarEffect.WandererKick);
            EffectHeadTiltCheck.IsChecked = _prefs.IsTopEffectEnabled(TopBarEffect.HeadTilt);
            EffectRollCheck.IsChecked = _prefs.IsTopEffectEnabled(TopBarEffect.WindowRoll);
            EffectSleepCheck.IsChecked = _prefs.IsTopEffectEnabled(TopBarEffect.YawnSleep);
            UpdateEffectCheckboxGuards();

            TapSitCheck.IsChecked = _prefs.IsTopTapPoseEnabled(TopTapPose.SitSmile);
            TapLoafCheck.IsChecked = _prefs.IsTopTapPoseEnabled(TopTapPose.LoafCalm);
            TapBigHeadCheck.IsChecked = _prefs.IsTopTapPoseEnabled(TopTapPose.BigHeadPeek);
            TapSleepCheck.IsChecked = _prefs.IsTopTapPoseEnabled(TopTapPose.Sleep);
            UpdateTapCheckboxGuards();

            ShyRetreatCheck.IsChecked = _prefs.ShyRetreatEnabled;
            TypingPauseCheck.IsChecked = _prefs.TypingPauseEnabled;
            ClimbPawsCheck.IsChecked = _prefs.ClimbPawsPeekEnabled;
        }
        finally
        {
            _isLoading = false;
        }
    }

    private static void SelectComboTag<T>(System.Windows.Controls.ComboBox combo, T value) where T : struct, Enum
    {
        foreach (ComboBoxItem item in combo.Items)
        {
            if (item.Tag is T t && EqualityComparer<T>.Default.Equals(t, value))
            {
                combo.SelectedItem = item;
                break;
            }
        }
    }

    private void UpdateEffectCheckboxGuards()
    {
        bool masterOn = _prefs.TopEffectsEnabled;
        int count = _prefs.OrderedEnabledTopEffects.Count;
        EffectPatrolCheck.IsEnabled = masterOn && !(count == 1 && _prefs.IsTopEffectEnabled(TopBarEffect.Patrol));
        EffectFlashCheck.IsEnabled = masterOn && !(count == 1 && _prefs.IsTopEffectEnabled(TopBarEffect.FlashStep));
        EffectBearCheck.IsEnabled = masterOn && !(count == 1 && _prefs.IsTopEffectEnabled(TopBarEffect.BearShake));
        EffectKickCheck.IsEnabled = masterOn && !(count == 1 && _prefs.IsTopEffectEnabled(TopBarEffect.WandererKick));
        EffectHeadTiltCheck.IsEnabled = masterOn && !(count == 1 && _prefs.IsTopEffectEnabled(TopBarEffect.HeadTilt));
        EffectRollCheck.IsEnabled = masterOn && !(count == 1 && _prefs.IsTopEffectEnabled(TopBarEffect.WindowRoll));
        EffectSleepCheck.IsEnabled = masterOn && !(count == 1 && _prefs.IsTopEffectEnabled(TopBarEffect.YawnSleep));
    }

    private void UpdateTapCheckboxGuards()
    {
        int count = _prefs.OrderedEnabledTopTapPoses.Count;
        TapSitCheck.IsEnabled = !(count == 1 && _prefs.IsTopTapPoseEnabled(TopTapPose.SitSmile));
        TapLoafCheck.IsEnabled = !(count == 1 && _prefs.IsTopTapPoseEnabled(TopTapPose.LoafCalm));
        TapBigHeadCheck.IsEnabled = !(count == 1 && _prefs.IsTopTapPoseEnabled(TopTapPose.BigHeadPeek));
        TapSleepCheck.IsEnabled = !(count == 1 && _prefs.IsTopTapPoseEnabled(TopTapPose.Sleep));
    }

    private void PetSpeciesRadio_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoading) return;
        if (CatRadio.IsChecked == true) _prefs.PetSpecies = PetSpecies.GoldenCat;
        else if (LabradorRadio.IsChecked == true) _prefs.PetSpecies = PetSpecies.Labrador;
        else if (ChinchillaRadio.IsChecked == true) _prefs.PetSpecies = PetSpecies.Chinchilla;
        else _prefs.PetSpecies = PetSpecies.Westie;
    }

    private void ScaleSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isLoading) return;
        _prefs.DogScale = e.NewValue;
        ScaleValueText.Text = CompanionPreferences.FormatScale(_prefs.DogScale);
    }

    private void ScalePreset_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button btn &&
            double.TryParse(btn.Tag?.ToString(), CultureInfo.InvariantCulture, out double val))
        {
            _prefs.DogScale = val;
        }
    }

    private void SwitchDelaySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isLoading) return;
        _prefs.WindowSwitchDelaySeconds = e.NewValue;
        SwitchDelayText.Text = CompanionPreferences.FormatDuration(_prefs.WindowSwitchDelaySeconds);
    }

    private void PerchPreferenceCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoading) return;
        if (PerchPreferenceCombo.SelectedItem is ComboBoxItem item && item.Tag is PerchPreference pref)
        {
            _prefs.PerchPreference = pref;
            _onPerchChanged();
        }
    }

    private void ClimbEnabledCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoading) return;
        _prefs.ClimbToTopEnabled = ClimbEnabledCheck.IsChecked == true;
    }

    private void ClimbIntervalSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isLoading) return;
        _prefs.ClimbToTopIntervalSeconds = e.NewValue;
        ClimbIntervalText.Text = CompanionPreferences.FormatDuration(_prefs.ClimbToTopIntervalSeconds);
    }

    private void ClimbPreset_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button btn &&
            double.TryParse(btn.Tag?.ToString(), CultureInfo.InvariantCulture, out double secs))
        {
            _prefs.ClimbToTopEnabled = true;
            _prefs.ClimbToTopIntervalSeconds = secs;
        }
    }

    private void TopEffectsEnabledCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoading) return;
        _prefs.TopEffectsEnabled = TopEffectsEnabledCheck.IsChecked == true;
        UpdateEffectCheckboxGuards();
    }

    private void EffectIntervalSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isLoading) return;
        _prefs.TopEffectIntervalSeconds = e.NewValue;
        EffectIntervalText.Text = CompanionPreferences.FormatDuration(_prefs.TopEffectIntervalSeconds);
    }

    private void EffectPreset_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button btn &&
            double.TryParse(btn.Tag?.ToString(), CultureInfo.InvariantCulture, out double secs))
        {
            _prefs.TopEffectsEnabled = true;
            _prefs.TopEffectIntervalSeconds = secs;
        }
    }

    private void TopEffect_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoading) return;
        if (sender == EffectPatrolCheck) _prefs.SetTopEffect(TopBarEffect.Patrol, EffectPatrolCheck.IsChecked == true);
        else if (sender == EffectFlashCheck) _prefs.SetTopEffect(TopBarEffect.FlashStep, EffectFlashCheck.IsChecked == true);
        else if (sender == EffectBearCheck) _prefs.SetTopEffect(TopBarEffect.BearShake, EffectBearCheck.IsChecked == true);
        else if (sender == EffectKickCheck) _prefs.SetTopEffect(TopBarEffect.WandererKick, EffectKickCheck.IsChecked == true);
        else if (sender == EffectHeadTiltCheck) _prefs.SetTopEffect(TopBarEffect.HeadTilt, EffectHeadTiltCheck.IsChecked == true);
        else if (sender == EffectRollCheck) _prefs.SetTopEffect(TopBarEffect.WindowRoll, EffectRollCheck.IsChecked == true);
        else if (sender == EffectSleepCheck) _prefs.SetTopEffect(TopBarEffect.YawnSleep, EffectSleepCheck.IsChecked == true);
        UpdateEffectCheckboxGuards();
    }

    private void PlayEffect_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button btn &&
            Enum.TryParse<TopBarEffect>(btn.Tag?.ToString(), out var eff))
        {
            _onPlayEffect(eff);
        }
    }

    private void TopTapPose_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoading) return;
        if (sender == TapSitCheck) _prefs.SetTopTapPose(TopTapPose.SitSmile, TapSitCheck.IsChecked == true);
        else if (sender == TapLoafCheck) _prefs.SetTopTapPose(TopTapPose.LoafCalm, TapLoafCheck.IsChecked == true);
        else if (sender == TapBigHeadCheck) _prefs.SetTopTapPose(TopTapPose.BigHeadPeek, TapBigHeadCheck.IsChecked == true);
        else if (sender == TapSleepCheck) _prefs.SetTopTapPose(TopTapPose.Sleep, TapSleepCheck.IsChecked == true);
        UpdateTapCheckboxGuards();
    }

    private void MicroToggle_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoading) return;
        _prefs.ShyRetreatEnabled = ShyRetreatCheck.IsChecked == true;
        _prefs.TypingPauseEnabled = TypingPauseCheck.IsChecked == true;
        _prefs.ClimbPawsPeekEnabled = ClimbPawsCheck.IsChecked == true;
    }

    private void Reset_Click(object sender, RoutedEventArgs e) => _prefs.ResetToDefaults();
    private void PreviewPeek_Click(object sender, RoutedEventArgs e) => _onPreviewPeek();
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
