import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class StartView extends WatchUi.View {
    private var service as MatchService;

    function initialize(service as MatchService) {
        View.initialize();
        self.service = service;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, height / 4, Graphics.FONT_MEDIUM, "Padel Score", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, height / 4 + 28, Graphics.FONT_XTINY, "Tap to start match", Graphics.TEXT_JUSTIFY_CENTER);

        UiHelpers.drawPrimaryButton(dc, "Start Match", width / 2 - 80, height / 2, 160, 50, UiHelpers.COLOR_ACCENT);

        if (service.archivedMatches.size() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, height - 36, Graphics.FONT_XTINY, "Swipe up for history", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

class StartDelegate extends WatchUi.BehaviorDelegate {
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

        if (x >= width / 2 - 80 && x <= width / 2 + 80 && y >= height / 2 && y <= height / 2 + 50) {
            var settings = new MatchSettings();
            settings.goldenPointEnabled = service.getGoldenPointEnabled();
            settings.fixedServerPositions = !service.getRotateServeEnabled();
            service.startMatch(settings);
            WatchUi.popView(WatchUi.SLIDE_LEFT);
            WatchUi.pushView(new SelectServerView(service), new SelectServerDelegate(service), WatchUi.SLIDE_LEFT);
            return true;
        }
        return false;
    }

    function onSwipe(swipeEvent as SwipeEvent) as Boolean {
        if (swipeEvent.getDirection() == WatchUi.SWIPE_UP && service.archivedMatches.size() > 0) {
            var history = new HistoryView(service);
            WatchUi.pushView(history, new HistoryDelegate(history), WatchUi.SLIDE_UP);
            return true;
        }
        return false;
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new SettingsView(service), new SettingsDelegate(service), WatchUi.SLIDE_UP);
        return true;
    }
}
