import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class MatchCompleteView extends WatchUi.View {
    private var service as MatchService;

    function initialize(service as MatchService) {
        View.initialize();
        self.service = service;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var match = service.activeMatch;
        if (match == null) {
            return;
        }

        var width = dc.getWidth();
        var height = dc.getHeight();

        var title = match.status == MatchStatus.COMPLETED ? "Match Complete" : "Match Ended";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, 24, Graphics.FONT_SMALL, title, Graphics.TEXT_JUSTIFY_CENTER);

        if (match.winner != null) {
            var winnerLabel = match.winner == Side.LEFT ? "Us win!" : "They win!";
            dc.setColor(match.winner == Side.LEFT ? UiHelpers.COLOR_LEFT : UiHelpers.COLOR_RIGHT, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, 52, Graphics.FONT_MEDIUM, winnerLabel, Graphics.TEXT_JUSTIFY_CENTER);
        }

        var summary = match.finalScoreSummary();
        if (summary.length() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, 84, Graphics.FONT_SMALL, summary, Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, 108, Graphics.FONT_XTINY, UiHelpers.formatDuration(UiHelpers.matchDuration(match)), Graphics.TEXT_JUSTIFY_CENTER);

        UiHelpers.drawPrimaryButton(dc, "Done", width / 2 - 70, height - 70, 140, 44, UiHelpers.COLOR_ACCENT);
    }
}

class MatchCompleteDelegate extends WatchUi.BehaviorDelegate {
    private var service as MatchService;

    function initialize(service as MatchService) {
        BehaviorDelegate.initialize();
        self.service = service;
    }

    function onTap(clickEvent as ClickEvent) as Boolean {
        var coords = clickEvent.getCoordinates();
        var width = System.getDeviceSettings().screenWidth;
        var height = System.getDeviceSettings().screenHeight;
        var x = coords[0];
        var y = coords[1];

        if (x >= width / 2 - 70 && x <= width / 2 + 70 && y >= height - 70 && y <= height - 26) {
            service.acknowledgeCompletedMatch();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            WatchUi.pushView(new StartView(service), new StartDelegate(service), WatchUi.SLIDE_RIGHT);
            return true;
        }
        return false;
    }
}
