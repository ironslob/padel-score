import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class PadelScoreApp extends Application.AppBase {
    var matchService as MatchService;

    function initialize() {
        AppBase.initialize();
        matchService = new MatchService();
    }

    function onStart(state as Dictionary or Null) as Void {
    }

    function onStop(state as Dictionary or Null) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        matchService.restore();
        return buildRootNavigation(matchService);
    }
}

function getApp() as PadelScoreApp {
    return Application.getApp() as PadelScoreApp;
}

function returnToStart(service as MatchService) as Void {
    service.discardMatch();
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    WatchUi.pushView(new StartView(service), new StartDelegate(service), WatchUi.SLIDE_RIGHT);
}

function buildRootNavigation(service as MatchService) as [Views] or [Views, InputDelegates] {
    var match = service.activeMatch;
    if (match == null) {
        return [new StartView(service), new StartDelegate(service)];
    }
    if (match.status == IN_PROGRESS) {
        if (match.needsWarmUp) {
            return [new WarmUpView(service), new WarmUpDelegate(service)];
        }
        if (match.needsServerSelection) {
            return [new SelectServerView(service), new SelectServerDelegate(service, true)];
        }
        var pager = new MatchPagerView(service, 1);
        return [pager, new MatchPagerDelegate(service, pager)];
    }
    if (match.status == COMPLETED || match.status == ENDED_EARLY) {
        return [new MatchCompleteView(service), new MatchCompleteDelegate(service)];
    }
    return [new StartView(service), new StartDelegate(service)];
}
