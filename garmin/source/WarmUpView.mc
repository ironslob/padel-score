import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class WarmUpView extends WatchUi.View {
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
        UiHelpers.drawHeader(dc, "Warm up");

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(
            width / 2,
            height / 2 - 28,
            Graphics.FONT_NUMBER_MEDIUM,
            UiHelpers.formatDuration(match.warmUpElapsed(Time.now().value()) * 1000),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        UiHelpers.drawPrimaryButton(dc, "Play", width / 2 - 70, height / 2 + 24, 140, 44, Graphics.COLOR_GREEN);
        UiHelpers.drawPrimaryButton(dc, "Back", width / 2 - 70, height / 2 + 76, 140, 36, Graphics.COLOR_DK_GRAY);
    }
}

class WarmUpDelegate extends WatchUi.BehaviorDelegate {
    private var service as MatchService;
    private var tickTimer as Timer.Timer or Null;
    private var didAdvance as Boolean;

    function initialize(service as MatchService) {
        BehaviorDelegate.initialize();
        self.service = service;
        didAdvance = false;
        tickTimer = new Timer.Timer();
        tickTimer.start(method(:onTick), 250, true);
    }

    function onTick() as Void {
        var match = service.activeMatch;
        if (match == null) {
            stopTimer();
            return;
        }
        if (match.isWarmUpExpired(Time.now().value())) {
            advance();
            return;
        }
        WatchUi.requestUpdate();
    }

    function onTap(clickEvent as ClickEvent) as Boolean {
        var coords = clickEvent.getCoordinates();
        var width = System.getDeviceSettings().screenWidth;
        var height = System.getDeviceSettings().screenHeight;
        var x = coords[0];
        var y = coords[1];
        if (x >= width / 2 - 70 && x <= width / 2 + 70 && y >= height / 2 + 24 && y <= height / 2 + 68) {
            advance();
            return true;
        }
        if (x >= width / 2 - 70 && x <= width / 2 + 70 && y >= height / 2 + 76 && y <= height / 2 + 112) {
            goBack();
            return true;
        }
        return false;
    }

    function onBack() as Boolean {
        goBack();
        return true;
    }

    private function advance() as Void {
        if (didAdvance) {
            return;
        }
        didAdvance = true;
        stopTimer();
        service.completeWarmUp();
        WatchUi.popView(WatchUi.SLIDE_LEFT);
        WatchUi.pushView(
            new SelectServerView(service),
            new SelectServerDelegate(service, true),
            WatchUi.SLIDE_LEFT
        );
    }

    private function goBack() as Void {
        if (didAdvance) {
            return;
        }
        didAdvance = true;
        stopTimer();
        returnToStart(service);
    }

    private function stopTimer() as Void {
        if (tickTimer != null) {
            tickTimer.stop();
            tickTimer = null;
        }
    }
}
