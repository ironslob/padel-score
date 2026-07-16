import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class SettingsView extends WatchUi.View {
    private var service as MatchService;

    function initialize(service as MatchService) {
        View.initialize();
        self.service = service;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        UiHelpers.drawHeader(dc, "Settings");

        var goldenPoint = service.getGoldenPointEnabled();
        var label = goldenPoint ? "Golden Point: On" : "Golden Point: Off";
        var color = goldenPoint ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY;

        UiHelpers.drawPrimaryButton(dc, label, 16, 40, width - 32, 44, color);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, 100, Graphics.FONT_XTINY, "Tap to toggle", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, dc.getHeight() - 20, Graphics.FONT_XTINY, "Swipe right to close", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class SettingsDelegate extends WatchUi.BehaviorDelegate {
    private var service as MatchService;

    function initialize(service as MatchService) {
        BehaviorDelegate.initialize();
        self.service = service;
    }

    function onTap(clickEvent as ClickEvent) as Boolean {
        var coords = clickEvent.getCoordinates();
        var y = coords[1];
        if (y >= 40 && y <= 84) {
            service.setGoldenPointEnabled(!service.getGoldenPointEnabled());
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function onSwipe(swipeEvent as SwipeEvent) as Boolean {
        if (swipeEvent.getDirection() == WatchUi.SWIPE_RIGHT) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        return false;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
