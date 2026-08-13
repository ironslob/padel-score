import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

function pushSettingsView(service as MatchService) as Void {
    var view = new SettingsView(service);
    WatchUi.pushView(view, new SettingsDelegate(service, view), WatchUi.SLIDE_UP);
}

class SettingsView extends WatchUi.View {
    private var service as MatchService;
    private var scrollIndex as Number;

    function initialize(service as MatchService) {
        View.initialize();
        self.service = service;
        scrollIndex = 0;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        UiHelpers.drawHeader(dc, "Settings");

        var labels = settingLabels();
        var y = 36;
        var shown = 0;
        for (var i = scrollIndex; i < labels.size() && shown < 4; i += 1) {
            var color = i == 0 && service.getDeuceFormat() == DeuceFormat.DEUCE_ADVANTAGE
                ? Graphics.COLOR_DK_GRAY
                : Graphics.COLOR_GREEN;
            if (i == 1) {
                color = service.getRotateServeEnabled() ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY;
            } else if (i == 2) {
                color = service.getUsThemLabels() ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY;
            } else if (i == 3) {
                color = service.getAskServeAtSetStart() ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY;
            } else if (i == 4) {
                color = service.activeMatch == null ? Graphics.COLOR_DK_BLUE : Graphics.COLOR_DK_GRAY;
            }
            UiHelpers.drawPrimaryButton(dc, labels[i], 16, y, width - 32, 36, color);
            y += 44;
            shown += 1;
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, dc.getHeight() - 16, Graphics.FONT_XTINY, "Tap to change", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function settingLabels() as Array<String> {
        var deuce = "Deuce: " + deuceFormatLabel(service.getDeuceFormat());
        var swap = service.getRotateServeEnabled() ? "Swap Sides: On" : "Swap Sides: Off";
        var labels = service.getUsThemLabels() ? "Labels: Us/Them" : "Labels: Serve";
        var ask = service.getAskServeAtSetStart() ? "Ask Serve: On" : "Ask Serve: Off";
        var length = "Length: " + matchSetFormatLabel(service.getMatchSetFormat());
        return [deuce, swap, labels, ask, length] as Array<String>;
    }

    function getScrollIndex() as Number {
        return scrollIndex;
    }

    function setScrollIndex(value as Number) as Void {
        scrollIndex = value;
    }
}

class SettingsDelegate extends WatchUi.BehaviorDelegate {
    private var service as MatchService;
    private var view as SettingsView;

    function initialize(service as MatchService, settingsView as SettingsView) {
        BehaviorDelegate.initialize();
        self.service = service;
        view = settingsView;
    }

    function onTap(clickEvent as ClickEvent) as Boolean {
        var coords = clickEvent.getCoordinates();
        var y = coords[1];
        var row = ((y - 36) / 44).toNumber();
        if (row < 0 || row > 3) {
            return false;
        }
        var index = view.getScrollIndex() + row;
        if (index == 0) {
            service.cycleDeuceFormat();
        } else if (index == 1) {
            service.setRotateServeEnabled(!service.getRotateServeEnabled());
        } else if (index == 2) {
            service.cycleUsThemLabels();
        } else if (index == 3) {
            service.cycleAskServeAtSetStart();
        } else if (index == 4) {
            if (service.activeMatch != null) {
                return true;
            }
            service.cycleMatchSetFormat();
        } else {
            return false;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onSwipe(swipeEvent as SwipeEvent) as Boolean {
        var direction = swipeEvent.getDirection();
        if (direction == WatchUi.SWIPE_RIGHT) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        if (direction == WatchUi.SWIPE_UP && view.getScrollIndex() + 4 < 5) {
            view.setScrollIndex(view.getScrollIndex() + 1);
            WatchUi.requestUpdate();
            return true;
        }
        if (direction == WatchUi.SWIPE_DOWN && view.getScrollIndex() > 0) {
            view.setScrollIndex(view.getScrollIndex() - 1);
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
