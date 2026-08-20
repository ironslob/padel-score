import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class SelectServerView extends WatchUi.View {
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

        UiHelpers.drawHeader(dc, "Who is serving?");
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, 28, Graphics.FONT_XTINY, "Tap your side", Graphics.TEXT_JUSTIFY_CENTER);

        var buttonY = height / 2 - 10;
        var buttonH = 56;
        var buttonW = width / 2 - 16;
        UiHelpers.drawPrimaryButton(dc, "Us", 8, buttonY, buttonW, buttonH, UiHelpers.COLOR_LEFT);
        UiHelpers.drawPrimaryButton(dc, "Them", width / 2 + 8, buttonY, buttonW, buttonH, UiHelpers.COLOR_RIGHT);

        var match = service.activeMatch;
        if (match != null && match.isWaitingForFirstServe()) {
            UiHelpers.drawPrimaryButton(dc, "Back", width / 2 - 70, height - 70, 140, 40, Graphics.COLOR_DK_GRAY);
        }
    }
}

class SelectServerDelegate extends WatchUi.BehaviorDelegate {
    private var service as MatchService;
    private var pushPagerAfter as Boolean;

    function initialize(service as MatchService, pushPagerAfter as Boolean) {
        BehaviorDelegate.initialize();
        self.service = service;
        self.pushPagerAfter = pushPagerAfter;
    }

    function onTap(clickEvent as ClickEvent) as Boolean {
        var coords = clickEvent.getCoordinates();
        var x = coords[0];
        var y = coords[1];
        var width = System.getDeviceSettings().screenWidth;
        var height = System.getDeviceSettings().screenHeight;
        var match = service.activeMatch;

        if (match != null && match.isWaitingForFirstServe()) {
            if (x >= width / 2 - 70 && x <= width / 2 + 70 && y >= height - 70 && y <= height - 30) {
                returnToStart(service);
                return true;
            }
            var buttonY = height / 2 - 10;
            if (y < buttonY || y > buttonY + 56) {
                return false;
            }
        }

        var side = x < width / 2 ? Side.LEFT : Side.RIGHT;
        service.selectServer(side);
        WatchUi.popView(WatchUi.SLIDE_LEFT);
        if (pushPagerAfter) {
            var pager = new MatchPagerView(service, 1);
            WatchUi.pushView(pager, new MatchPagerDelegate(service, pager), WatchUi.SLIDE_LEFT);
        } else {
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onBack() as Boolean {
        var match = service.activeMatch;
        if (match != null && match.isWaitingForFirstServe()) {
            returnToStart(service);
            return true;
        }
        // Between sets a server still has to be chosen, or scoring is blocked.
        return true;
    }
}
