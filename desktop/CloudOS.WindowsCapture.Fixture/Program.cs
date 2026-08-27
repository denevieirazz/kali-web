using System.Drawing;
using System.Windows.Forms;

ApplicationConfiguration.Initialize();
using var form = new CaptureFixtureForm();
Application.Run(form);

sealed class CaptureFixtureForm : Form
{
    private readonly System.Windows.Forms.Timer _timer;
    private readonly Button _inputButton;
    private readonly TextBox _inputBox;
    private int _frame;
    private int _clickCount;
    private int _keyCount;
    private string _lastKey = "none";

    public CaptureFixtureForm()
    {
        Text = "CloudOS Windows Capture Fixture";
        StartPosition = FormStartPosition.Manual;
        Location = new Point(120, 120);
        ClientSize = new Size(640, 420);
        DoubleBuffered = true;

        _inputButton = new Button
        {
            Name = "CloudOSInputButton",
            Text = "CloudOS input target",
            Location = new Point(24, 250),
            Size = new Size(190, 42),
            TabIndex = 0
        };
        _inputButton.Click += (_, _) =>
        {
            _clickCount++;
            UpdateObservableState();
        };
        _inputButton.KeyDown += OnObservedKeyDown;

        _inputBox = new TextBox
        {
            Name = "CloudOSInputTextBox",
            Location = new Point(24, 316),
            Size = new Size(300, 30),
            TabIndex = 1,
            PlaceholderText = "targeted keyboard input"
        };
        _inputBox.KeyDown += OnObservedKeyDown;

        Controls.Add(_inputButton);
        Controls.Add(_inputBox);

        _timer = new System.Windows.Forms.Timer { Interval = 50 };
        _timer.Tick += (_, _) =>
        {
            _frame++;
            Invalidate();
        };
        _timer.Start();

        Shown += (_, _) =>
        {
            _inputButton.Focus();
            UpdateObservableState();
        };
    }

    private void OnObservedKeyDown(object? sender, KeyEventArgs e)
    {
        _keyCount++;
        _lastKey = e.KeyCode.ToString();
        UpdateObservableState();
    }

    private void UpdateObservableState()
    {
        Text = $"CloudOS Windows Capture Fixture | clicks={_clickCount} | keys={_keyCount} | last={_lastKey}";
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        var bounds = ClientRectangle;
        var travel = Math.Max(1, bounds.Width - 100);
        var x = 20 + ((_frame * 9) % travel);

        using var titleFont = new Font(Font.FontFamily, 18, FontStyle.Bold);
        using var bodyFont = new Font(Font.FontFamily, 11, FontStyle.Regular);
        using var brush = new SolidBrush(SystemColors.ControlText);
        using var accentBrush = new SolidBrush(SystemColors.Highlight);

        e.Graphics.DrawString("CloudOS WGC physical fixture", titleFont, brush, 24, 24);
        e.Graphics.DrawString($"frame={_frame}", bodyFont, brush, 24, 72);
        e.Graphics.DrawString($"input: clicks={_clickCount} keys={_keyCount} last={_lastKey}", bodyFont, brush, 24, 102);
        e.Graphics.FillRectangle(accentBrush, x, 150, 80, 70);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _timer.Stop();
            _timer.Dispose();
        }

        base.Dispose(disposing);
    }
}
