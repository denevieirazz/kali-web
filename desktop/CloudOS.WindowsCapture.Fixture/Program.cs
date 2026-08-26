using System.Drawing;
using System.Windows.Forms;

ApplicationConfiguration.Initialize();
using var form = new CaptureFixtureForm();
Application.Run(form);

sealed class CaptureFixtureForm : Form
{
    private readonly System.Windows.Forms.Timer _timer;
    private int _frame;

    public CaptureFixtureForm()
    {
        Text = "CloudOS Windows Capture Fixture";
        StartPosition = FormStartPosition.Manual;
        Location = new Point(120, 120);
        ClientSize = new Size(640, 420);
        DoubleBuffered = true;

        _timer = new System.Windows.Forms.Timer { Interval = 50 };
        _timer.Tick += (_, _) =>
        {
            _frame++;
            Invalidate();
        };
        _timer.Start();
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
        e.Graphics.FillRectangle(accentBrush, x, 130, 80, 80);
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
