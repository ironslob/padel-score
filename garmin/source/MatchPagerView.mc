import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Three-page pager: overview (0), score (1), actions (2).
class MatchPagerView extends WatchUi.View {
    var service as MatchService;
    var page as Number;
    var undoProgressLeft as Float;
    var undoProgressRight as Float;

    function initialize(service as MatchService, page as Number) {
        View.initialize();
        self.service = service;
        self.page = page;
        undoProgressLeft = 0.0;
        undoProgressRight = 0.0;
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
            drawOverviewPage(dc, match);
        } else if (page == 1) {
            drawScorePage(dc, match);
        } else {
            drawActionsPage(dc, match);
        }

        UiHelpers.drawPageDots(dc, page, 3);
    }

    private function drawScorePage(dc as Dc, match as MatchState) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var game = match.scoreScreenGameDisplay();
        var games = match.scoreScreenSetDisplay();
        var roles = match.servingRoleLabels();
        var sides = match.scoreScreenSides();

        if (match.currentGame.isTieBreak) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, 16, Graphics.FONT_XTINY, "Tie-break", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (match.currentGame.isGoldenPointActive) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            var decidingLabel = deuceFormatDecidingPointLabel(match.settings.deuceFormat);
            dc.drawText(width / 2, 16, Graphics.FONT_XTINY, decidingLabel, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, 16, Graphics.FONT_SMALL, games[0] + " – " + games[1], Graphics.TEXT_JUSTIFY_CENTER);
        }

        var notice = match.currentGame.tieBreakNotice();
        if (notice != null) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            dc.drawText(width / 2, 32, Graphics.FONT_XTINY, notice, Graphics.TEXT_JUSTIFY_CENTER);
        }

        var buttonY = height / 2 - 20;
        var buttonH = height / 2 - 30;
        var buttonW = width / 2 - 10;

        var leftColor = sides[0] == Side.LEFT ? UiHelpers.COLOR_LEFT : UiHelpers.COLOR_RIGHT;
        var rightColor = sides[1] == Side.LEFT ? UiHelpers.COLOR_LEFT : UiHelpers.COLOR_RIGHT;
        var leftServing = match.currentServer != null && match.currentServer == sides[0];
        var rightServing = match.currentServer != null && match.currentServer == sides[1];

        drawScoreButton(dc, game[0], roles[0], 6, buttonY, buttonW, buttonH, leftColor, leftServing, undoProgressLeft);
        drawScoreButton(dc, game[1], roles[1], width / 2 + 4, buttonY, buttonW, buttonH, rightColor, rightServing, undoProgressRight);
    }

    private function drawScoreButton(dc as Dc, score as String, role as String, x as Number, y as Number, w as Number, h as Number, color as Number, isServing as Boolean, undoProgress as Float) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, 14);
        if (undoProgress > 0) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, y, w, h, 14);
            dc.fillRectangle(x, y, (w * undoProgress).toNumber(), 4);
        }
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
        UiHelpers.drawHeader(dc, "Actions");

        var keys = actionKeys(match);
        var y = 32;
        var buttonH = 32;
        var buttonW = width - 32;
        for (var i = 0; i < keys.size(); i += 1) {
            var key = keys[i];
            var label = actionLabel(key);
            var color = actionColor(key);
            if (key.equals("undo") && !service.canUndo()) {
                color = Graphics.COLOR_DK_GRAY;
            }
            UiHelpers.drawPrimaryButton(dc, label, 16, y, buttonW, buttonH, color);
            y += buttonH + 6;
        }
    }

    function actionKeys(match as MatchState) as Array<String> {
        var keys = ["undo"] as Array<String>;
        if (match.canChooseNewServer()) {
            keys.add("newServe");
        }
        keys.add("finish");
        keys.add("endEarly");
        keys.add("discard");
        keys.add("settings");
        return keys;
    }

    private function actionLabel(key as String) as String {
        if (key.equals("undo")) { return "Undo"; }
        if (key.equals("newServe")) { return "New Serve"; }
        if (key.equals("finish")) { return "Finish"; }
        if (key.equals("endEarly")) { return "End Early"; }
        if (key.equals("discard")) { return "Discard"; }
        return "Settings";
    }

    private function actionColor(key as String) as Number {
        if (key.equals("undo")) { return Graphics.COLOR_DK_BLUE; }
        if (key.equals("newServe")) { return Graphics.COLOR_PINK; }
        if (key.equals("finish")) { return Graphics.COLOR_GREEN; }
        if (key.equals("endEarly")) { return Graphics.COLOR_ORANGE; }
        if (key.equals("discard")) { return Graphics.COLOR_RED; }
        return Graphics.COLOR_DK_GRAY;
    }
}

class MatchPagerDelegate extends WatchUi.BehaviorDelegate {
    var service as MatchService;
    var view as MatchPagerView;
    private var undoSide as Side or Null;
    private var undoStartedAt as Number or Null;
    private var undoStartedMs as Number or Null;
    private var undoTimer as Timer.Timer or Null;

    function initialize(service as MatchService, pagerView as MatchPagerView) {
        BehaviorDelegate.initialize();
        self.service = service;
        view = pagerView;
        undoSide = null;
        undoStartedAt = null;
        undoStartedMs = null;
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

        if (view.page == 1) {
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

        var visual = x < width / 2 ? Side.LEFT : Side.RIGHT;
        var side = match.logicalSideForVisual(visual);
        var now = Time.now().value();

        if (undoSide == side && undoStartedAt != null && (now - undoStartedAt) < MatchSettings.QUICK_UNDO_TIMEOUT_MS) {
            clearUndoWindow();
            service.undoLastPoint();
            checkMatchComplete(null, service.activeMatch);
            WatchUi.requestUpdate();
            return true;
        }

        service.awardPoint(side);
        var updated = service.activeMatch;
        checkMatchComplete(match, updated);
        if (service.activeMatch != null && service.activeMatch.status == MatchStatus.IN_PROGRESS
            && !didPointEndGame(match, service.activeMatch)) {
            startUndoWindow(side, now);
        }
        WatchUi.requestUpdate();
        return true;
    }

    private function handleActionsTap(x as Number, y as Number, width as Number) as Boolean {
        var match = service.activeMatch;
        if (match == null || x < 16 || x > width - 16) {
            return false;
        }
        var keys = view.actionKeys(match);
        var row = ((y - 32) / 38).toNumber();
        if (row < 0 || row >= keys.size()) {
            return false;
        }
        var key = keys[row];
        if (key.equals("undo") && service.canUndo()) {
            service.undoLastPoint();
            checkMatchComplete(null, service.activeMatch);
            WatchUi.requestUpdate();
            return true;
        } else if (key.equals("newServe")) {
            service.requestServerSelection();
            WatchUi.pushView(new SelectServerView(service), new SelectServerDelegate(service, false), WatchUi.SLIDE_LEFT);
            return true;
        } else if (key.equals("finish")) {
            confirmAction("Finish this match?", 1);
            return true;
        } else if (key.equals("endEarly")) {
            confirmAction("End match early?", 2);
            return true;
        } else if (key.equals("discard")) {
            confirmAction("Discard match?", 3);
            return true;
        } else if (key.equals("settings")) {
            pushSettingsView(service);
            return true;
        }
        return false;
    }

    private function confirmAction(message as String, action as Number) as Void {
        WatchUi.pushView(
            new WatchUi.Confirmation(message),
            new MatchActionConfirmDelegate(service, action),
            WatchUi.SLIDE_IMMEDIATE
        );
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
        undoStartedMs = System.getTimer();
        if (undoTimer == null) {
            undoTimer = new Timer.Timer();
        }
        undoTimer.stop();
        undoTimer.start(method(:onUndoTick), 100, true);
        updateUndoProgress();
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(50, 200)]);
        }
    }

    function onUndoTick() as Void {
        if (undoStartedMs == null) {
            return;
        }
        var elapsed = System.getTimer() - undoStartedMs;
        if (elapsed >= MatchSettings.QUICK_UNDO_TIMEOUT_MS) {
            clearUndoWindow();
            WatchUi.requestUpdate();
            return;
        }
        updateUndoProgress();
        WatchUi.requestUpdate();
    }

    private function updateUndoProgress() as Void {
        if (undoStartedMs == null || undoSide == null || service.activeMatch == null) {
            view.undoProgressLeft = 0.0;
            view.undoProgressRight = 0.0;
            return;
        }
        var progress = (System.getTimer() - undoStartedMs).toFloat() / MatchSettings.QUICK_UNDO_TIMEOUT_MS.toFloat();
        if (progress > 1) {
            progress = 1;
        }
        var visual = service.activeMatch.visualSideForLogical(undoSide);
        if (visual == Side.LEFT) {
            view.undoProgressLeft = progress;
            view.undoProgressRight = 0.0;
        } else {
            view.undoProgressLeft = 0.0;
            view.undoProgressRight = progress;
        }
    }

    function onUndoTimeout() as Void {
        clearUndoWindow();
        WatchUi.requestUpdate();
    }

    private function clearUndoWindow() as Void {
        undoSide = null;
        undoStartedAt = null;
        undoStartedMs = null;
        view.undoProgressLeft = 0.0;
        view.undoProgressRight = 0.0;
        if (undoTimer != null) {
            undoTimer.stop();
        }
    }

    private function didPointEndGame(previous as MatchState, updated as MatchState) as Boolean {
        if (previous.status != MatchStatus.IN_PROGRESS || updated.status != MatchStatus.IN_PROGRESS) {
            return false;
        }
        var oldGames = previous.currentSet.leftGames + previous.currentSet.rightGames;
        var newGames = updated.currentSet.leftGames + updated.currentSet.rightGames;
        return updated.completedSets.size() > previous.completedSets.size() || newGames > oldGames;
    }

    private function checkMatchComplete(previous as MatchState or Null, updated as MatchState or Null) as Void {
        var match = updated != null ? updated : service.activeMatch;
        if (match == null) {
            return;
        }
        if (match.status == MatchStatus.COMPLETED || match.status == MatchStatus.ENDED_EARLY) {
            navigateToComplete();
            return;
        }
        if (previous != null && didPointEndGame(previous, match)) {
            var completedSet = match.completedSets.size() > previous.completedSets.size();
            var isTieBreak = match.currentGame.isTieBreak && !previous.currentGame.isTieBreak;
            var interstitial = new GameInterstitialView(service, completedSet, isTieBreak);
            WatchUi.pushView(interstitial, new GameInterstitialDelegate(service, interstitial), WatchUi.SLIDE_UP);
            return;
        }
        if (match.needsServerSelection) {
            WatchUi.popView(WatchUi.SLIDE_LEFT);
            WatchUi.pushView(new SelectServerView(service), new SelectServerDelegate(service, true), WatchUi.SLIDE_LEFT);
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

class MatchActionConfirmDelegate extends WatchUi.ConfirmationDelegate {
    private var service as MatchService;
    private var action as Number;

    function initialize(service as MatchService, action as Number) {
        ConfirmationDelegate.initialize();
        self.service = service;
        self.action = action;
    }

    function onResponse(response) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            if (action == 1) {
                service.finishMatch();
                WatchUi.popView(WatchUi.SLIDE_LEFT);
                WatchUi.pushView(new MatchCompleteView(service), new MatchCompleteDelegate(service), WatchUi.SLIDE_LEFT);
            } else if (action == 2) {
                service.endMatchEarly();
                WatchUi.popView(WatchUi.SLIDE_LEFT);
                WatchUi.pushView(new MatchCompleteView(service), new MatchCompleteDelegate(service), WatchUi.SLIDE_LEFT);
            } else if (action == 3) {
                service.discardMatch();
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
                WatchUi.pushView(new StartView(service), new StartDelegate(service), WatchUi.SLIDE_RIGHT);
            }
        }
        return true;
    }
}
