import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class WristRallyApp extends Application.AppBase {
    var matchService as MatchService;

    function initialize() {
        AppBase.initialize();
        matchService = new MatchService();
    }

    function onStart(state as Dictionary or Null) as Void {
    }

    function onStop(state as Dictionary or Null) as Void {
        matchService.saveFitSessionOnStop();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        matchService.restore();
        return buildRootNavigation(matchService);
    }
}

function getApp() as WristRallyApp {
    return Application.getApp() as WristRallyApp;
}

function makeStartPair(service as MatchService) as [Views, InputDelegates] {
    var view = new StartView(service);
    return [view, new StartDelegate(service, view)];
}

function pushStartView(service as MatchService, slide as Number) as Void {
    var view = new StartView(service);
    WatchUi.pushView(view, new StartDelegate(service, view), slide);
}

function makeWarmUpPair(service as MatchService) as [Views, InputDelegates] {
    var view = new WarmUpView(service);
    return [view, new WarmUpDelegate(service, view)];
}

function pushWarmUpView(service as MatchService) as Void {
    var view = new WarmUpView(service);
    WatchUi.pushView(view, new WarmUpDelegate(service, view), WatchUi.SLIDE_LEFT);
}

function pushHistoryView(service as MatchService) as Void {
    var view = new HistoryView(service);
    WatchUi.pushView(view, new HistoryDelegate(view), WatchUi.SLIDE_UP);
}

function pushCompleteView(service as MatchService, slide as Number) as Void {
    var view = new MatchCompleteView(service);
    WatchUi.pushView(view, new MatchCompleteDelegate(service), slide);
}

function returnToStart(service as MatchService) as Void {
    service.discardMatch();
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    pushStartView(service, WatchUi.SLIDE_RIGHT);
}

function pushMatchStartViews(service as MatchService) as Void {
    var match = service.activeMatch;
    if (match != null && match.needsWarmUp) {
        pushWarmUpView(service);
    } else {
        WatchUi.pushView(new SelectServerView(service), new SelectServerDelegate(service, true), WatchUi.SLIDE_LEFT);
    }
}

function buildRootNavigation(service as MatchService) as [Views] or [Views, InputDelegates] {
    var match = service.activeMatch;
    if (match == null) {
        return makeStartPair(service);
    }
    if (match.status == IN_PROGRESS) {
        if (match.needsWarmUp) {
            return makeWarmUpPair(service);
        }
        if (match.needsServerSelection) {
            return [new SelectServerView(service), new SelectServerDelegate(service, true)];
        }
        var pager = new MatchPagerView(service, 1);
        return [pager, new MatchPagerDelegate(service, pager)];
    }
    if (match.status == COMPLETED || match.status == ENDED_EARLY) {
        var complete = new MatchCompleteView(service);
        return [complete, new MatchCompleteDelegate(service)];
    }
    return makeStartPair(service);
}
