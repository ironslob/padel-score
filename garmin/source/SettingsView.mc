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

        var deuceFormat = service.getDeuceFormat();
        var deuceLabel = "Deuce: " + deuceFormatLabel(deuceFormat);
        // Regular is the "plain" option, so it reads as unset like the toggles below.
        var deuceColor = deuceFormat == DeuceFormat.DEUCE_ADVANTAGE
            ? Graphics.COLOR_DK_GRAY
            : Graphics.COLOR_GREEN;
        UiHelpers.drawPrimaryButton(dc, deuceLabel, 16, 40, width - 32, 44, deuceColor);

        var rotateServe = service.getRotateServeEnabled();
        var rotateLabel = rotateServe ? "Swap Sides: On" : "Swap Sides: Off";
        var rotateColor = rotateServe ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY;
        UiHelpers.drawPrimaryButton(dc, rotateLabel, 16, 96, width - 32, 44, rotateColor);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, 156, Graphics.FONT_XTINY, "Tap to change", Graphics.TEXT_JUSTIFY_CENTER);
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
            service.cycleDeuceFormat();
            WatchUi.requestUpdate();
            return true;
        }
        if (y >= 96 && y <= 140) {
            service.setRotateServeEnabled(!service.getRotateServeEnabled());
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
