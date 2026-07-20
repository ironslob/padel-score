import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Three-page pager: score (0), overview (1), actions (2).
class MatchPagerView extends WatchUi.View {
    var service as MatchService;
    var page as Number;

    function initialize(service as MatchService, page as Number) {
        View.initialize();
        self.service = service;
        self.page = page;
    }

    function setPage(newPage as Number) as Void {
        page = newPage;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var match = service.activeMatch;
        if (match == null) {
            return;
        }

        if (page == 0) {
            drawScorePage(dc, match);
        } else if (page == 1) {
            drawOverviewPage(dc, match);
        } else {
            drawActionsPage(dc, match);
        }

        UiHelpers.drawPageDots(dc, page, 3);
    }

    private function drawScorePage(dc as Dc, match as MatchState) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var game = match.currentGame.displayPair();
        var games = match.currentSet.displayPair();
        var roles = match.servingRoleLabels();

        if (match.currentGame.isTieBreak) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, 16, Graphics.FONT_XTINY, "Tie-break", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (match.currentGame.isGoldenPointActive) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, 16, Graphics.FONT_XTINY, "Golden Point", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, 16, Graphics.FONT_SMALL, games[0] + " – " + games[1], Graphics.TEXT_JUSTIFY_CENTER);
        }

        var notice = match.currentGame.tieBreakNotice(match.settings.fixedServerPositions);
        if (notice != null) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, 32, Graphics.FONT_XTINY, notice, Graphics.TEXT_JUSTIFY_CENTER);
        }

        var buttonY = height / 2 - 20;
        var buttonH = height / 2 - 30;
        var buttonW = width / 2 - 10;

        var leftServing = match.currentServer == Side.LEFT;
        var rightServing = match.currentServer == Side.RIGHT;

        drawScoreButton(dc, game[0], roles[0], 6, buttonY, buttonW, buttonH, UiHelpers.COLOR_LEFT, leftServing);
        drawScoreButton(dc, game[1], roles[1], width / 2 + 4, buttonY, buttonW, buttonH, UiHelpers.COLOR_RIGHT, rightServing);
    }

    private function drawScoreButton(dc as Dc, score as String, role as String, x as Number, y as Number, w as Number, h as Number, color as Number, isServing as Boolean) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, 14);
        if (isServing) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + w / 2, y + 14, 4);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w / 2, y + h / 2 - 16, Graphics.FONT_NUMBER_HOT, score, Graphics.TEXT_JUSTIFY_CENTER);
        if (role.length() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w / 2, y + h - 18, Graphics.FONT_XTINY, role, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawOverviewPage(dc as Dc, match as MatchState) as Void {
        var width = dc.getWidth();
        UiHelpers.drawHeader(dc, "Overview");

        var sets = match.matchSetsDisplay();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, 36, Graphics.FONT_MEDIUM, "Sets " + sets[0] + " – " + sets[1], Graphics.TEXT_JUSTIFY_CENTER);

        var lines = match.setScoreLines();
        var y = 64;
        for (var i = 0; i < lines.size() && i < 5; i += 1) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, y, Graphics.FONT_SMALL, "Set " + (i + 1).toString() + ": " + lines[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += 24;
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, dc.getHeight() - 28, Graphics.FONT_XTINY, UiHelpers.formatDuration(UiHelpers.matchDuration(match)), Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawActionsPage(dc as Dc, match as MatchState) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        UiHelpers.drawHeader(dc, "Actions");

        var y = 36;
        var buttonH = 36;
        var buttonW = width - 32;

        UiHelpers.drawPrimaryButton(dc, "Undo", 16, y, buttonW, buttonH, service.canUndo() ? Graphics.COLOR_DK_BLUE : Graphics.COLOR_DK_GRAY);
        y += buttonH + 8;
        UiHelpers.drawPrimaryButton(dc, "Finish", 16, y, buttonW, buttonH, Graphics.COLOR_GREEN);
        y += buttonH + 8;
        UiHelpers.drawPrimaryButton(dc, "End Early", 16, y, buttonW, buttonH, Graphics.COLOR_ORANGE);
        y += buttonH + 8;
        UiHelpers.drawPrimaryButton(dc, "Discard", 16, y, buttonW, buttonH, Graphics.COLOR_RED);
    }
}

class MatchPagerDelegate extends WatchUi.BehaviorDelegate {
    var service as MatchService;
    var view as MatchPagerView;
    private var undoSide as Side or Null;
    private var undoStartedAt as Number or Null;
    private var undoTimer as Timer.Timer or Null;

    function initialize(service as MatchService, pagerView as MatchPagerView) {
        BehaviorDelegate.initialize();
        self.service = service;
        view = pagerView;
        undoSide = null;
        undoStartedAt = null;
        undoTimer = null;
    }

    function onTap(clickEvent as ClickEvent) as Boolean {
        var match = service.activeMatch;
        if (match == null) {
            return false;
        }

        var coords = clickEvent.getCoordinates();
        var x = coords[0];
        var y = coords[1];
        var width = System.getDeviceSettings().screenWidth;
        var height = System.getDeviceSettings().screenHeight;

        if (view.page == 0) {
            return handleScoreTap(x, y, width, height, match);
        } else if (view.page == 2) {
            return handleActionsTap(x, y, width);
        }
        return false;
    }

    private function handleScoreTap(x as Number, y as Number, width as Number, height as Number, match as MatchState) as Boolean {
        var buttonY = height / 2 - 20;
        var buttonH = height / 2 - 30;
        if (y < buttonY || y > buttonY + buttonH) {
            return false;
        }

        var side = x < width / 2 ? Side.LEFT : Side.RIGHT;
        var now = Time.now().value();

        if (undoSide == side && undoStartedAt != null && (now - undoStartedAt) < MatchSettings.QUICK_UNDO_TIMEOUT_MS) {
            clearUndoWindow();
            service.undoLastPoint();
            checkMatchComplete();
            WatchUi.requestUpdate();
            return true;
        }

        service.awardPoint(side);
        checkMatchComplete();
        if (service.activeMatch != null && service.activeMatch.status == MatchStatus.IN_PROGRESS) {
            startUndoWindow(side, now);
        }
        WatchUi.requestUpdate();
        return true;
    }

    private function handleActionsTap(x as Number, y as Number, width as Number) as Boolean {
        if (x < 16 || x > width - 16) {
            return false;
        }
        var row = (y - 36) / 44;
        if (row == 0 && service.canUndo()) {
            service.undoLastPoint();
            checkMatchComplete();
            WatchUi.requestUpdate();
            return true;
        } else if (row == 1) {
            service.finishMatch();
            navigateToComplete();
            return true;
        } else if (row == 2) {
            service.endMatchEarly();
            navigateToComplete();
            return true;
        } else if (row == 3) {
            service.discardMatch();
            navigateToStart();
            return true;
        }
        return false;
    }

    function onSwipe(swipeEvent as SwipeEvent) as Boolean {
        var direction = swipeEvent.getDirection();
        if (direction == WatchUi.SWIPE_LEFT && view.page < 2) {
            view.setPage(view.page + 1);
            return true;
        } else if (direction == WatchUi.SWIPE_RIGHT && view.page > 0) {
            view.setPage(view.page - 1);
            return true;
        }
        return false;
    }

    function onNextPage() as Boolean {
        if (view.page < 2) {
            view.setPage(view.page + 1);
            return true;
        }
        return false;
    }

    function onPreviousPage() as Boolean {
        if (view.page > 0) {
            view.setPage(view.page - 1);
            return true;
        }
        return false;
    }

    function onBack() as Boolean {
        if (view.page > 0) {
            view.setPage(view.page - 1);
            return true;
        }
        return false;
    }

    private function startUndoWindow(side as Side, at as Number) as Void {
        undoSide = side;
        undoStartedAt = at;
        if (undoTimer == null) {
            undoTimer = new Timer.Timer();
        }
        undoTimer.stop();
        undoTimer.start(method(:onUndoTimeout), MatchSettings.QUICK_UNDO_TIMEOUT_MS, false);
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(50, 200)]);
        }
    }

    function onUndoTimeout() as Void {
        clearUndoWindow();
        WatchUi.requestUpdate();
    }

    private function clearUndoWindow() as Void {
        undoSide = null;
        undoStartedAt = null;
        if (undoTimer != null) {
            undoTimer.stop();
        }
    }

    private function checkMatchComplete() as Void {
        var match = service.activeMatch;
        if (match != null && (match.status == MatchStatus.COMPLETED || match.status == MatchStatus.ENDED_EARLY)) {
            navigateToComplete();
        } else if (match != null && match.needsServerSelection) {
            WatchUi.popView(WatchUi.SLIDE_LEFT);
            WatchUi.pushView(new SelectServerView(service), new SelectServerDelegate(service), WatchUi.SLIDE_LEFT);
        }
    }

    private function navigateToComplete() as Void {
        WatchUi.popView(WatchUi.SLIDE_LEFT);
        WatchUi.pushView(new MatchCompleteView(service), new MatchCompleteDelegate(service), WatchUi.SLIDE_LEFT);
    }

    private function navigateToStart() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.pushView(new StartView(service), new StartDelegate(service), WatchUi.SLIDE_RIGHT);
    }
}
