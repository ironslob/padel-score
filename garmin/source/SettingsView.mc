import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

function pushSettingsView(service as MatchService) as Void {
    var view = new SettingsView(service);
    WatchUi.pushView(view, new SettingsDelegate(service, view), WatchUi.SLIDE_UP);
}

class SettingsView extends WatchUi.View {
    private var service as MatchService;
    private var scrollIndex as Number;
    var focusIndex as Number;

    function initialize(service as MatchService) {
        View.initialize();
        self.service = service;
        scrollIndex = 0;
        focusIndex = 0;
    }

    function settingKeys() as Array<String> {
        var keys = ["deuce", "swap", "labels", "ask", "length", "warm", "limit"] as Array<String>;
        if (ButtonInput.isTouchScreen()) {
            keys.add("buttons");
        }
        return keys;
    }

    function visibleRowCount(height as Number) as Number {
        var available = height - 36 - 22;
        var count = available / 44;
        if (count < 2) {
            count = 2;
        }
        if (count > 4) {
            count = 4;
        }
        return count;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        UiHelpers.drawHeader(dc, "Settings");

        var keys = settingKeys();
        ensureFocusVisible(height);
        var visible = visibleRowCount(height);
        var y = 36;
        var shown = 0;
        for (var i = scrollIndex; i < keys.size() && shown < visible; i += 1) {
            UiHelpers.drawPrimaryButton(dc, settingLabel(keys[i]), 16, y, width - 32, 36, settingColor(keys[i]));
            if (ButtonInput.needsButtonNav() && i == focusIndex) {
                UiHelpers.drawFocusOutline(dc, 16, y, width - 32, 36);
            }
            y += 44;
            shown += 1;
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        var hint = ButtonInput.needsButtonNav() ? "Select to change" : "Tap to change";
        dc.drawText(width / 2, dc.getHeight() - 16, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function settingLabel(key as String) as String {
        if (key.equals("deuce")) {
            return "Deuce: " + deuceFormatLabel(service.getDeuceFormat());
        }
        if (key.equals("swap")) {
            return service.getRotateServeEnabled() ? "Swap Sides: On" : "Swap Sides: Off";
        }
        if (key.equals("labels")) {
            return service.getUsThemLabels() ? "Labels: Us/Them" : "Labels: Serve";
        }
        if (key.equals("ask")) {
            return service.getAskServeAtSetStart() ? "Ask Serve: On" : "Ask Serve: Off";
        }
        if (key.equals("length")) {
            return "Length: " + matchSetFormatLabel(service.getMatchSetFormat());
        }
        if (key.equals("warm")) {
            return service.getWarmUpEnabled() ? "Warm-up: On" : "Warm-up: Off";
        }
        if (key.equals("limit")) {
            return service.getWarmUpMinutes() == 0
                ? "Limit: None"
                : "Limit: " + service.getWarmUpMinutes().toString() + " min";
        }
        return ButtonInput.scoringModeLabel(service.getButtonScoringMode());
    }

    function settingColor(key as String) as Number {
        if (key.equals("deuce")) {
            return service.getDeuceFormat() == DEUCE_ADVANTAGE
                ? Graphics.COLOR_DK_GRAY
                : Graphics.COLOR_GREEN;
        }
        if (key.equals("swap")) {
            return service.getRotateServeEnabled() ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY;
        }
        if (key.equals("labels")) {
            return service.getUsThemLabels() ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY;
        }
        if (key.equals("ask")) {
            return service.getAskServeAtSetStart() ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY;
        }
        if (key.equals("buttons")) {
            return Graphics.COLOR_DK_BLUE;
        }
        if (key.equals("length") || key.equals("limit")) {
            return service.activeMatch == null ? Graphics.COLOR_DK_BLUE : Graphics.COLOR_DK_GRAY;
        }
        if (key.equals("warm")) {
            if (service.activeMatch != null) {
                return Graphics.COLOR_DK_GRAY;
            }
            return service.getWarmUpEnabled() ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY;
        }
        return Graphics.COLOR_DK_GRAY;
    }

    function getScrollIndex() as Number {
        return scrollIndex;
    }

    function setScrollIndex(value as Number) as Void {
        scrollIndex = value;
    }

    function ensureFocusVisible(height as Number) as Void {
        var keys = settingKeys();
        if (focusIndex < 0) {
            focusIndex = 0;
        }
        if (focusIndex >= keys.size()) {
            focusIndex = keys.size() - 1;
        }
        var visible = visibleRowCount(height);
        var maxScroll = keys.size() - visible;
        if (maxScroll < 0) {
            maxScroll = 0;
        }
        if (focusIndex < scrollIndex) {
            scrollIndex = focusIndex;
        }
        if (focusIndex >= scrollIndex + visible) {
            scrollIndex = focusIndex - visible + 1;
        }
        if (scrollIndex > maxScroll) {
            scrollIndex = maxScroll;
        }
        if (scrollIndex < 0) {
            scrollIndex = 0;
        }
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
        var height = System.getDeviceSettings().screenHeight;
        var visible = view.visibleRowCount(height);
        var row = ((y - 36) / 44).toNumber();
        if (row < 0 || row >= visible) {
            return false;
        }
        var keys = view.settingKeys();
        var index = view.getScrollIndex() + row;
        if (index < 0 || index >= keys.size()) {
            return false;
        }
        return cycleKey(keys[index]);
    }

    function onSwipe(swipeEvent as SwipeEvent) as Boolean {
        var direction = swipeEvent.getDirection();
        if (direction == WatchUi.SWIPE_RIGHT) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        var keys = view.settingKeys();
        var height = System.getDeviceSettings().screenHeight;
        var visible = view.visibleRowCount(height);
        if (direction == WatchUi.SWIPE_UP && view.getScrollIndex() + visible < keys.size()) {
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

    function onSelect() as Boolean {
        if (!ButtonInput.needsButtonNav()) {
            return false;
        }
        var keys = view.settingKeys();
        view.ensureFocusVisible(System.getDeviceSettings().screenHeight);
        return cycleKey(keys[view.focusIndex]);
    }

    function onNextPage() as Boolean {
        if (!ButtonInput.needsButtonNav()) {
            return false;
        }
        view.focusIndex += 1;
        view.ensureFocusVisible(System.getDeviceSettings().screenHeight);
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        if (!ButtonInput.needsButtonNav()) {
            return false;
        }
        view.focusIndex -= 1;
        view.ensureFocusVisible(System.getDeviceSettings().screenHeight);
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    private function cycleKey(key as String) as Boolean {
        if (key.equals("deuce")) {
            service.cycleDeuceFormat();
        } else if (key.equals("swap")) {
            service.setRotateServeEnabled(!service.getRotateServeEnabled());
        } else if (key.equals("labels")) {
            service.cycleUsThemLabels();
        } else if (key.equals("ask")) {
            service.cycleAskServeAtSetStart();
        } else if (key.equals("length")) {
            if (service.activeMatch != null) {
                return true;
            }
            service.cycleMatchSetFormat();
        } else if (key.equals("warm")) {
            if (service.activeMatch != null) {
                return true;
            }
            service.cycleWarmUpEnabled();
        } else if (key.equals("limit")) {
            if (service.activeMatch != null) {
                return true;
            }
            service.cycleWarmUpMinutes();
        } else if (key.equals("buttons")) {
            service.cycleButtonScoringMode();
        } else {
            return false;
        }
        WatchUi.requestUpdate();
        return true;
    }
}
