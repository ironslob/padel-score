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

    function initialize(service as MatchService, completedSet as Boolean, isTieBreak as Boolean) {
        View.initialize();
        self.service = service;
        self.completedSet = completedSet;
        self.isTieBreak = isTieBreak;
        startedAt = System.getTimer();
        timeoutMs = completedSet ? 0 : MatchSettings.QUICK_UNDO_TIMEOUT_MS;
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
        dc.drawText(width / 2, 44, Graphics.FONT_SMALL, "Games " + games[0] + " – " + games[1], Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, 66, Graphics.FONT_XTINY, "Sets " + sets[0] + " – " + sets[1], Graphics.TEXT_JUSTIFY_CENTER);

        var buttonY = height / 2 + 4;
        var buttonH = 40;
        var buttonW = width / 2 - 14;
        UiHelpers.drawPrimaryButton(dc, "Undo", 8, buttonY, buttonW, buttonH, Graphics.COLOR_ORANGE);
        var nextLabel = completedSet ? "Next set" : "Next";
        UiHelpers.drawPrimaryButton(dc, nextLabel, width / 2 + 6, buttonY, buttonW, buttonH, Graphics.COLOR_GREEN);

        if (completedSet && match.canChooseNewServer()) {
            UiHelpers.drawPrimaryButton(dc, "New serve", 16, buttonY + buttonH + 10, width - 32, 36, Graphics.COLOR_DK_BLUE);
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

        if (view.completedSet && match.canChooseNewServer() && y >= buttonY + buttonH + 10 && y <= buttonY + buttonH + 46) {
            service.requestServerSelection();
            stopTimer();
            WatchUi.popView(WatchUi.SLIDE_LEFT);
            WatchUi.pushView(new SelectServerView(service), new SelectServerDelegate(service, false), WatchUi.SLIDE_LEFT);
            return true;
        }
        return false;
    }

    function onBack() as Boolean {
        dismiss();
        return true;
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
