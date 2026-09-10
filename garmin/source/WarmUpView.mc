import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class WarmUpView extends WatchUi.View {
    private var service as MatchService;
    var focusIndex as Number;

    function initialize(service as MatchService) {
        View.initialize();
        self.service = service;
        focusIndex = 0;
    }

    function playFrame(width as Number, height as Number) as Array<Number> {
        var compact = height < 220;
        var y = compact ? height - 90 : height / 2 + 24;
        return [width / 2 - 70, y, 140, compact ? 36 : 44] as Array<Number>;
    }

    function backFrame(width as Number, height as Number) as Array<Number> {
        var compact = height < 220;
        var y = compact ? height - 48 : height / 2 + 76;
        return [width / 2 - 70, y, 140, 36] as Array<Number>;
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

        var play = playFrame(width, height);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(
            width / 2,
            play[1] - 44,
            Graphics.FONT_NUMBER_MEDIUM,
            UiHelpers.formatDuration(match.warmUpElapsed(Time.now().value()) * 1000),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        UiHelpers.drawPrimaryButton(dc, "Play", play[0], play[1], play[2], play[3], Graphics.COLOR_GREEN);
        var back = backFrame(width, height);
        UiHelpers.drawPrimaryButton(dc, "Back", back[0], back[1], back[2], back[3], Graphics.COLOR_DK_GRAY);
        if (ButtonInput.needsButtonNav()) {
            var focus = focusIndex == 0 ? play : back;
            UiHelpers.drawFocusOutline(dc, focus[0], focus[1], focus[2], focus[3]);
        }
    }
}

class WarmUpDelegate extends WatchUi.BehaviorDelegate {
    private var service as MatchService;
    private var view as WarmUpView;
    private var tickTimer as Timer.Timer or Null;
    private var didAdvance as Boolean;

    function initialize(service as MatchService, warmUpView as WarmUpView) {
        BehaviorDelegate.initialize();
        self.service = service;
        view = warmUpView;
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
        var play = view.playFrame(width, height);
        if (x >= play[0] && x <= play[0] + play[2] && y >= play[1] && y <= play[1] + play[3]) {
            advance();
            return true;
        }
        var back = view.backFrame(width, height);
        if (x >= back[0] && x <= back[0] + back[2] && y >= back[1] && y <= back[1] + back[3]) {
            goBack();
            return true;
        }
        return false;
    }

    function onSelect() as Boolean {
        if (!ButtonInput.needsButtonNav()) {
            return false;
        }
        if (view.focusIndex == 0) {
            advance();
        } else {
            goBack();
        }
        return true;
    }

    function onNextPage() as Boolean {
        if (!ButtonInput.needsButtonNav()) {
            return false;
        }
        view.focusIndex = 1;
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        if (!ButtonInput.needsButtonNav()) {
            return false;
        }
        view.focusIndex = 0;
        WatchUi.requestUpdate();
        return true;
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
