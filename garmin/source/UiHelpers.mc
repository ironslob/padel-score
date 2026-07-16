// Shared drawing helpers for all views.

module UiHelpers {
    const COLOR_LEFT = Graphics.COLOR_BLUE;
    const COLOR_RIGHT = Graphics.COLOR_RED;
    const COLOR_MUTED = Graphics.COLOR_DK_GRAY;
    const COLOR_ACCENT = 0x1E88E5;

    function screenSize() as Array<Number> {
        var settings = System.getDeviceSettings();
        return [settings.screenWidth, settings.screenHeight] as Array<Number>;
    }

    function drawHeader(dc as Dc, title as String) as Void {
        var width = dc.getWidth();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, 8, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawPageDots(dc as Dc, page as Number, total as Number) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var y = height - 14;
        var spacing = 12;
        var startX = width / 2 - ((total - 1) * spacing) / 2;
        for (var i = 0; i < total; i += 1) {
            dc.setColor(i == page ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(startX + i * spacing, y, i == page ? 3 : 2);
        }
    }

    function drawPrimaryButton(dc as Dc, label as String, x as Number, y as Number, w as Number, h as Number, fillColor as Number) as Void {
        dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, 12);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w / 2, y + h / 2 - 8, Graphics.FONT_MEDIUM, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function formatDuration(ms as Number) as String {
        var totalSeconds = (ms / 1000).toNumber();
        var minutes = totalSeconds / 60;
        var seconds = totalSeconds % 60;
        return minutes.format("%d") + ":" + seconds.format("%02d");
    }

    function matchDuration(match as MatchState) as Number {
        var end = match.finishedAt != null ? match.finishedAt : Time.now().value();
        return end - match.startedAt;
    }
}
