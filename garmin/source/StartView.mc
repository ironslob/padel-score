import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class StartView extends WatchUi.View {
    private var service as MatchService;
    var focusIndex as Number;

    function initialize(service as MatchService) {
        View.initialize();
        self.service = service;
        focusIndex = 0;
    }

    function menuItems() as Array<String> {
        var items = ["start", "settings"] as Array<String>;
        if (service.archivedMatches.size() > 0) {
            items.add("history");
        }
        return items;
    }

    function itemFrame(index as Number, width as Number, height as Number) as Array<Number> {
        var count = menuItems().size();
        var compact = height < 240 || count > 2;
        var btnW = compact ? width - 32 : 160;
        var x = (width - btnW) / 2;
        var startH = compact ? 40 : 50;
        var otherH = compact ? 32 : 40;
        var gap = compact ? 6 : 8;
        var blockH = startH;
        if (count > 1) {
            blockH += (count - 1) * (otherH + gap);
        }
        var startY = height - 18 - blockH;
        if (startY < 48) {
            startY = 48;
        }
        var y = startY;
        for (var i = 0; i < index; i += 1) {
            y += (i == 0 ? startH : otherH) + gap;
        }
        var h = index == 0 ? startH : otherH;
        return [x, y, btnW, h] as Array<Number>;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var items = menuItems();
        var compact = height < 240 || items.size() > 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(
            width / 2,
            compact ? 8 : height / 4,
            compact ? Graphics.FONT_SMALL : Graphics.FONT_MEDIUM,
            "Wrist Rally",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        var hint = ButtonInput.needsButtonNav() ? "Select to start" : "Tap to start match";
        dc.drawText(
            width / 2,
            compact ? 26 : height / 4 + 28,
            Graphics.FONT_XTINY,
            hint,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        for (var i = 0; i < items.size(); i += 1) {
            var frame = itemFrame(i, width, height);
            var label = "Start Match";
            var color = UiHelpers.COLOR_ACCENT;
            if (items[i].equals("settings")) {
                label = "Settings";
                color = Graphics.COLOR_DK_GRAY;
            } else if (items[i].equals("history")) {
                label = "History";
                color = Graphics.COLOR_DK_BLUE;
            }
            UiHelpers.drawPrimaryButton(dc, label, frame[0], frame[1], frame[2], frame[3], color);
            if (ButtonInput.needsButtonNav() && i == focusIndex) {
                UiHelpers.drawFocusOutline(dc, frame[0], frame[1], frame[2], frame[3]);
            }
        }
    }

    function clampFocus() as Void {
        var count = menuItems().size();
        if (focusIndex < 0) {
            focusIndex = 0;
        }
        if (focusIndex >= count) {
            focusIndex = count - 1;
        }
    }
}

class StartDelegate extends WatchUi.BehaviorDelegate {
    private var service as MatchService;
    private var view as StartView;

    function initialize(service as MatchService, startView as StartView) {
        BehaviorDelegate.initialize();
        self.service = service;
        view = startView;
    }

    function onTap(clickEvent as ClickEvent) as Boolean {
        var coords = clickEvent.getCoordinates();
        var width = System.getDeviceSettings().screenWidth;
        var height = System.getDeviceSettings().screenHeight;
        var x = coords[0];
        var y = coords[1];
        var items = view.menuItems();
        for (var i = 0; i < items.size(); i += 1) {
            var frame = view.itemFrame(i, width, height);
            if (x >= frame[0] && x <= frame[0] + frame[2] && y >= frame[1] && y <= frame[1] + frame[3]) {
                return activateItem(items[i]);
            }
        }
        return false;
    }

    function onSwipe(swipeEvent as SwipeEvent) as Boolean {
        if (swipeEvent.getDirection() == WatchUi.SWIPE_UP && service.archivedMatches.size() > 0) {
            pushHistoryView(service);
            return true;
        }
        return false;
    }

    function onMenu() as Boolean {
        pushSettingsView(service);
        return true;
    }

    function onSelect() as Boolean {
        if (!ButtonInput.needsButtonNav()) {
            return false;
        }
        var items = view.menuItems();
        view.clampFocus();
        return activateItem(items[view.focusIndex]);
    }

    function onNextPage() as Boolean {
        if (!ButtonInput.needsButtonNav()) {
            return false;
        }
        view.focusIndex += 1;
        view.clampFocus();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        if (!ButtonInput.needsButtonNav()) {
            return false;
        }
        view.focusIndex -= 1;
        view.clampFocus();
        WatchUi.requestUpdate();
        return true;
    }

    private function activateItem(key as String) as Boolean {
        if (key.equals("start")) {
            startMatch();
            return true;
        }
        if (key.equals("settings")) {
            pushSettingsView(service);
            return true;
        }
        if (key.equals("history")) {
            pushHistoryView(service);
            return true;
        }
        return false;
    }

    private function startMatch() as Void {
        var settings = service.settingsForNewMatch();
        service.startMatch(settings);
        if (service.lastFitStartFailed) {
            WatchUi.pushView(
                new WatchUi.Confirmation(WatchUi.loadResource(Rez.Strings.fitConflictMessage) as String),
                new FitConflictConfirmDelegate(service),
                WatchUi.SLIDE_IMMEDIATE
            );
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_LEFT);
        pushMatchStartViews(service);
    }
}

class FitConflictConfirmDelegate extends WatchUi.ConfirmationDelegate {
    private var service as MatchService;

    function initialize(service as MatchService) {
        ConfirmationDelegate.initialize();
        self.service = service;
    }

    function onResponse(response) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            // Continue without recording — match already started.
            // Confirmation dismisses itself; pop StartView then push match flow.
            service.lastFitStartFailed = false;
            WatchUi.popView(WatchUi.SLIDE_LEFT);
            pushMatchStartViews(service);
        } else {
            service.discardMatch();
        }
        return true;
    }
}
