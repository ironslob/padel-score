import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class HistoryView extends WatchUi.View {
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
        UiHelpers.drawHeader(dc, "History");

        var matches = service.archivedMatches;
        if (matches.size() == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, dc.getHeight() / 2, Graphics.FONT_SMALL, "No matches yet", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var y = 32;
        var shown = 0;
        for (var i = scrollIndex; i < matches.size() && shown < 4; i += 1) {
            drawMatchRow(dc, matches[i], y, width);
            y += 36;
            shown += 1;
        }

        if (scrollIndex > 0 || scrollIndex + 4 < matches.size()) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, dc.getHeight() - 16, Graphics.FONT_XTINY, "Swipe to scroll", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawMatchRow(dc as Dc, match as MatchState, y as Number, width as Number) as Void {
        var sets = match.matchSetsDisplay();
        var line1 = sets[0] + " – " + sets[1] + "  " + statusDisplayName(match.status);
        var line2 = match.finalScoreSummary();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(12, y, Graphics.FONT_XTINY, line1, Graphics.TEXT_JUSTIFY_LEFT);
        if (line2.length() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(12, y + 16, Graphics.FONT_XTINY, line2, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function scrollUp() as Void {
        if (scrollIndex > 0) {
            scrollIndex -= 1;
            WatchUi.requestUpdate();
        }
    }

    function scrollDown() as Void {
        if (scrollIndex + 4 < service.archivedMatches.size()) {
            scrollIndex += 1;
            WatchUi.requestUpdate();
        }
    }
}

class HistoryDelegate extends WatchUi.BehaviorDelegate {
    private var view as HistoryView;

    function initialize(historyView as HistoryView) {
        BehaviorDelegate.initialize();
        view = historyView;
    }

    function onSwipe(swipeEvent as SwipeEvent) as Boolean {
        if (swipeEvent.getDirection() == WatchUi.SWIPE_UP) {
            view.scrollDown();
            return true;
        } else if (swipeEvent.getDirection() == WatchUi.SWIPE_DOWN) {
            view.scrollUp();
            return true;
        } else if (swipeEvent.getDirection() == WatchUi.SWIPE_RIGHT) {
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
