import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class GameInterstitialView extends WatchUi.View {
    var service as MatchService;
    var completedSet as Boolean;
    var isTieBreak as Boolean;
    var startedAt as Number;
    var timeoutMs as Number;
    var scrollIndex as Number;
    var focusIndex as Number;

    function initialize(service as MatchService, completedSet as Boolean, isTieBreak as Boolean) {
        View.initialize();
        self.service = service;
        self.completedSet = completedSet;
        self.isTieBreak = isTieBreak;
        startedAt = System.getTimer();
        timeoutMs = completedSet ? 0 : MatchSettings.QUICK_UNDO_TIMEOUT_MS;
        scrollIndex = 0;
        focusIndex = completedSet ? 0 : 1;
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
        var headline = completedSet ? "Set!" : (isTieBreak ? "Tie-break" : "Game!");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, 16, Graphics.FONT_MEDIUM, headline, Graphics.TEXT_JUSTIFY_CENTER);

        var games = match.currentSet.displayPair();
        if (completedSet && match.completedSets.size() > 0) {
            var finished = match.completedSets[match.completedSets.size() - 1];
            games = finished.displayPair();
        }
        var sets = match.matchSetsDisplay();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        if (match.isMatchTieBreak()) {
            dc.drawText(width / 2, 44, Graphics.FONT_SMALL, "Games " + games[0] + " – " + games[1], Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(width / 2, 66, Graphics.FONT_XTINY, "First to 10, win by 2", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (isTieBreak) {
            dc.drawText(width / 2, 44, Graphics.FONT_SMALL, "Games " + games[0] + " – " + games[1], Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(width / 2, 66, Graphics.FONT_XTINY, "First to 7, win by 2", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(width / 2, 44, Graphics.FONT_SMALL, "Games " + games[0] + " – " + games[1], Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(width / 2, 66, Graphics.FONT_XTINY, "Sets " + sets[0] + " – " + sets[1], Graphics.TEXT_JUSTIFY_CENTER);
        }

        if (completedSet) {
            drawSetActions(dc, match, width, height);
            return;
        }

        var buttonY = height / 2 + 4;
        var buttonH = 40;
        var buttonW = width / 2 - 14;
        UiHelpers.drawPrimaryButton(dc, "Undo", 8, buttonY, buttonW, buttonH, Graphics.COLOR_ORANGE);
        UiHelpers.drawPrimaryButton(dc, "Next", width / 2 + 6, buttonY, buttonW, buttonH, Graphics.COLOR_GREEN);
        if (ButtonInput.needsButtonNav()) {
            if (focusIndex == 0) {
                UiHelpers.drawFocusOutline(dc, 8, buttonY, buttonW, buttonH);
            } else {
                UiHelpers.drawFocusOutline(dc, width / 2 + 6, buttonY, buttonW, buttonH);
            }
        }

        if (timeoutMs > 0) {
            var elapsed = System.getTimer() - startedAt;
            var progress = elapsed.toFloat() / timeoutMs.toFloat();
            if (progress > 1) {
                progress = 1;
            }
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(width / 2 + 6, buttonY, ((buttonW) * progress).toNumber(), 3);
        }
    }

    // Continue, new serve, undo, then stop — most likely first, full-size, scroll for the rest.
    private function drawSetActions(dc as Dc, match as MatchState, width as Number, height as Number) as Void {
        var keys = actionKeys(match);
        clampScroll(keys, height);
        var visible = visibleButtonCount(height);
        var top = buttonAreaTop();
        var shown = 0;
        for (var i = scrollIndex; i < keys.size() && shown < visible; i += 1) {
            var key = keys[i];
            UiHelpers.drawPrimaryButton(
                dc,
                actionLabel(key),
                16,
                top + shown * (buttonHeight() + buttonGap()),
                width - 32,
                buttonHeight(),
                actionColor(key)
            );
            if (ButtonInput.needsButtonNav() && i == focusIndex) {
                UiHelpers.drawFocusOutline(
                    dc,
                    16,
                    top + shown * (buttonHeight() + buttonGap()),
                    width - 32,
                    buttonHeight()
                );
            }
            shown += 1;
        }

        if (scrollIndex > 0 || scrollIndex + visible < keys.size()) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
            var hint = ButtonInput.needsButtonNav() ? "Up/Down to scroll" : "Swipe to scroll";
            dc.drawText(width / 2, height - 14, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function actionKeys(match as MatchState) as Array<String> {
        var keys = ["next"] as Array<String>;
        if (match.canChooseNewServer()) {
            keys.add("newServe");
        }
        keys.add("undo");
        keys.add("endMatch");
        return keys;
    }

    function buttonAreaTop() as Number {
        return 90;
    }

    function buttonHeight() as Number {
        return 40;
    }

    function buttonGap() as Number {
        return 10;
    }

    function visibleButtonCount(height as Number) as Number {
        var available = height - buttonAreaTop() - 18;
        var row = buttonHeight() + buttonGap();
        var count = available / row;
        if (count < 1) {
            count = 1;
        }
        return count;
    }

    function scrollDown(match as MatchState, height as Number) as Void {
        var keys = actionKeys(match);
        var maxIndex = keys.size() - visibleButtonCount(height);
        if (maxIndex < 0) {
            maxIndex = 0;
        }
        if (scrollIndex < maxIndex) {
            scrollIndex += 1;
            WatchUi.requestUpdate();
        }
    }

    function scrollUp() as Void {
        if (scrollIndex > 0) {
            scrollIndex -= 1;
            WatchUi.requestUpdate();
        }
    }

    function moveFocus(delta as Number, match as MatchState, height as Number) as Void {
        var keys = actionKeys(match);
        var next = focusIndex + delta;
        if (next < 0) {
            next = 0;
        }
        if (next >= keys.size()) {
            next = keys.size() - 1;
        }
        focusIndex = next;
        var visible = visibleButtonCount(height);
        if (focusIndex < scrollIndex) {
            scrollIndex = focusIndex;
        }
        if (focusIndex >= scrollIndex + visible) {
            scrollIndex = focusIndex - visible + 1;
        }
        WatchUi.requestUpdate();
    }

    private function clampScroll(keys as Array<String>, height as Number) as Void {
        var maxIndex = keys.size() - visibleButtonCount(height);
        if (maxIndex < 0) {
            maxIndex = 0;
        }
        if (scrollIndex > maxIndex) {
            scrollIndex = maxIndex;
        }
        if (scrollIndex < 0) {
            scrollIndex = 0;
        }
    }

    private function actionLabel(key as String) as String {
        if (key.equals("next")) { return "Next set"; }
        if (key.equals("newServe")) { return "New serve"; }
        if (key.equals("undo")) { return "Undo"; }
        return "End match";
    }

    private function actionColor(key as String) as Number {
        if (key.equals("next")) { return Graphics.COLOR_GREEN; }
        if (key.equals("newServe")) { return Graphics.COLOR_DK_BLUE; }
        if (key.equals("undo")) { return Graphics.COLOR_ORANGE; }
        return Graphics.COLOR_RED;
    }
}

class GameInterstitialDelegate extends WatchUi.BehaviorDelegate {
    var service as MatchService;
    var view as GameInterstitialView;
    private var tickTimer as Timer.Timer or Null;

    function initialize(service as MatchService, interstitial as GameInterstitialView) {
        BehaviorDelegate.initialize();
        self.service = service;
        view = interstitial;
        if (interstitial.timeoutMs > 0) {
            tickTimer = new Timer.Timer();
            tickTimer.start(method(:onTick), 100, true);
        }
    }

    function onTick() as Void {
        if (view.timeoutMs <= 0) {
            return;
        }
        if ((System.getTimer() - view.startedAt) >= view.timeoutMs) {
            dismiss();
            return;
        }
        WatchUi.requestUpdate();
    }

    function onTap(clickEvent as ClickEvent) as Boolean {
        var match = service.activeMatch;
        if (match == null) {
            dismiss();
            return true;
        }
        var coords = clickEvent.getCoordinates();
        var x = coords[0];
        var y = coords[1];
        var width = System.getDeviceSettings().screenWidth;
        var height = System.getDeviceSettings().screenHeight;

        if (view.completedSet) {
            return handleSetTap(match, x, y, width, height);
        }

        var buttonY = height / 2 + 4;
        var buttonH = 40;

        if (y >= buttonY && y <= buttonY + buttonH) {
            if (x < width / 2) {
                service.undoLastPoint();
                dismiss();
                return true;
            }
            dismiss();
            return true;
        }
        return false;
    }

    function onSwipe(swipeEvent as SwipeEvent) as Boolean {
        if (!view.completedSet) {
            return false;
        }
        var match = service.activeMatch;
        if (match == null) {
            return false;
        }
        var height = System.getDeviceSettings().screenHeight;
        if (swipeEvent.getDirection() == WatchUi.SWIPE_UP) {
            view.scrollDown(match, height);
            return true;
        }
        if (swipeEvent.getDirection() == WatchUi.SWIPE_DOWN) {
            view.scrollUp();
            return true;
        }
        return false;
    }

    function onNextPage() as Boolean {
        if (!view.completedSet) {
            if (!ButtonInput.needsButtonNav()) {
                return false;
            }
            view.focusIndex = 1;
            WatchUi.requestUpdate();
            return true;
        }
        var match = service.activeMatch;
        if (match == null) {
            return false;
        }
        if (ButtonInput.needsButtonNav()) {
            view.moveFocus(1, match, System.getDeviceSettings().screenHeight);
            return true;
        }
        view.scrollDown(match, System.getDeviceSettings().screenHeight);
        return true;
    }

    function onPreviousPage() as Boolean {
        if (!view.completedSet) {
            if (!ButtonInput.needsButtonNav()) {
                return false;
            }
            view.focusIndex = 0;
            WatchUi.requestUpdate();
            return true;
        }
        if (ButtonInput.needsButtonNav()) {
            var match = service.activeMatch;
            if (match == null) {
                return false;
            }
            view.moveFocus(-1, match, System.getDeviceSettings().screenHeight);
            return true;
        }
        view.scrollUp();
        return true;
    }

    function onSelect() as Boolean {
        if (!ButtonInput.needsButtonNav()) {
            return false;
        }
        var match = service.activeMatch;
        if (match == null) {
            dismiss();
            return true;
        }
        if (!view.completedSet) {
            if (view.focusIndex == 0) {
                service.undoLastPoint();
            }
            dismiss();
            return true;
        }
        var keys = view.actionKeys(match);
        if (view.focusIndex < 0 || view.focusIndex >= keys.size()) {
            return false;
        }
        return handleSetAction(keys[view.focusIndex]);
    }

    function onBack() as Boolean {
        dismiss();
        return true;
    }

    private function handleSetTap(match as MatchState, x as Number, y as Number, width as Number, height as Number) as Boolean {
        var keys = view.actionKeys(match);
        var top = view.buttonAreaTop();
        var rowH = view.buttonHeight() + view.buttonGap();
        var visible = view.visibleButtonCount(height);
        if (x < 16 || x > width - 16) {
            return false;
        }
        var row = ((y - top) / rowH).toNumber();
        if (row < 0 || row >= visible) {
            return false;
        }
        var index = view.scrollIndex + row;
        if (index < 0 || index >= keys.size()) {
            return false;
        }
        var inButton = (y - top) - (row * rowH) <= view.buttonHeight();
        if (!inButton) {
            return false;
        }
        return handleSetAction(keys[index]);
    }

    private function handleSetAction(key as String) as Boolean {
        if (key.equals("next")) {
            dismiss();
            return true;
        }
        if (key.equals("newServe")) {
            service.requestServerSelection();
            stopTimer();
            WatchUi.popView(WatchUi.SLIDE_LEFT);
            WatchUi.pushView(new SelectServerView(service), new SelectServerDelegate(service, false), WatchUi.SLIDE_LEFT);
            return true;
        }
        if (key.equals("undo")) {
            if (service.canUndo()) {
                service.undoLastPoint();
                dismiss();
            }
            return true;
        }
        if (key.equals("endMatch")) {
            WatchUi.pushView(
                new WatchUi.Confirmation("End this match?"),
                new SetEndMatchConfirmDelegate(service),
                WatchUi.SLIDE_IMMEDIATE
            );
            return true;
        }
        return false;
    }

    private function dismiss() as Void {
        stopTimer();
        WatchUi.popView(WatchUi.SLIDE_LEFT);
        var match = service.activeMatch;
        if (match != null && match.needsServerSelection) {
            WatchUi.pushView(new SelectServerView(service), new SelectServerDelegate(service, false), WatchUi.SLIDE_LEFT);
        }
    }

    private function stopTimer() as Void {
        if (tickTimer != null) {
            tickTimer.stop();
            tickTimer = null;
        }
    }
}

class SetEndMatchConfirmDelegate extends WatchUi.ConfirmationDelegate {
    private var service as MatchService;

    function initialize(service as MatchService) {
        ConfirmationDelegate.initialize();
        self.service = service;
    }

    function onResponse(response) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            service.finishMatch();
            WatchUi.popView(WatchUi.SLIDE_LEFT);
            pushCompleteView(service, WatchUi.SLIDE_LEFT);
        }
        return true;
    }
}
