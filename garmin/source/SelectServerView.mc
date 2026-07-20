import Toybox.Graphics;
import Toybox.Lang;
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
    }
}

class SelectServerDelegate extends WatchUi.BehaviorDelegate {
    private var service as MatchService;

    function initialize(service as MatchService) {
        BehaviorDelegate.initialize();
        self.service = service;
    }

    function onTap(clickEvent as ClickEvent) as Boolean {
        var coords = clickEvent.getCoordinates();
        var x = coords[0];
        var width = System.getDeviceSettings().screenWidth;
        var side = x < width / 2 ? Side.LEFT : Side.RIGHT;
        service.selectServer(side);
        WatchUi.popView(WatchUi.SLIDE_LEFT);
        var pager = new MatchPagerView(service, 1);
        WatchUi.pushView(pager, new MatchPagerDelegate(service, pager), WatchUi.SLIDE_LEFT);
        return true;
    }
}
