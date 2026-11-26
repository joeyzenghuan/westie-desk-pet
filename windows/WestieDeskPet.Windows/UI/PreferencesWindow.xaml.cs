using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using WestieDeskPet.Core;

namespace WestieDeskPet.Windows.UI;

public partial class PreferencesWindow : Window
{
    private readonly CompanionPreferences _prefs;
    private readonly Action _onPreviewClimb;
    private readonly Action _onPreviewFlashStep;
    private readonly Action _onPerchChanged;
    private bool _isLoading;

    public PreferencesWindow(
        CompanionPreferences prefs,
        Action onPreviewClimb,
        Action onPreviewFlashStep,
        Action onPerchChanged)
    {
        _prefs = prefs;
        _onPreviewClimb = onPreviewClimb;
        _onPreviewFlashStep = onPreviewFlashStep;
        _onPerchChanged = onPerchChanged;

        InitializeComponent();

        foreach (var pp in Enum.GetValues<PerchPreference>())
            PerchPreferenceCombo.Items.Add(new ComboBoxItem { Content = pp.DisplayName(), Tag = pp });

        foreach (var rt in Enum.GetValues<TopClimbRoutine>())
            ClimbRoutineCombo.Items.Add(new ComboBoxItem { Content = rt.DisplayName(), Tag = rt });

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

            ScaleSlider.Value = _prefs.DogScale;
            ScaleValueText.Text = CompanionPreferences.FormatScale(_prefs.DogScale);

            SwitchDelaySlider.Value = _prefs.WindowSwitchDelaySeconds;
            SwitchDelayText.Text = CompanionPreferences.FormatDuration(_prefs.WindowSwitchDelaySeconds);

            SelectComboTag(PerchPreferenceCombo, _prefs.PerchPreference);
            SelectComboTag(ClimbRoutineCombo, _prefs.TopClimbRoutine);

            ClimbEnabledCheck.IsChecked = _prefs.ClimbToTopEnabled;
            ClimbIntervalSlider.Value = _prefs.ClimbToTopIntervalSeconds;
            ClimbIntervalText.Text = CompanionPreferences.FormatDuration(_prefs.ClimbToTopIntervalSeconds);
            ClimbIntervalSlider.IsEnabled = _prefs.ClimbToTopEnabled;
            ClimbRoutineCombo.IsEnabled = _prefs.ClimbToTopEnabled;

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
        _prefs.PetSpecies = CatRadio.IsChecked == true ? PetSpecies.GoldenCat : PetSpecies.Westie;
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

    private void ClimbRoutineCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoading) return;
        if (ClimbRoutineCombo.SelectedItem is ComboBoxItem item && item.Tag is TopClimbRoutine rt)
            _prefs.TopClimbRoutine = rt;
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
    private void PreviewClimb_Click(object sender, RoutedEventArgs e) => _onPreviewClimb();
    private void PreviewFlash_Click(object sender, RoutedEventArgs e) => _onPreviewFlashStep();
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
