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

    function onStop() as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        matchService.restore();
        return buildRootNavigation(matchService);
    }
}

function getApp() as PadelScoreApp {
    return Application.getApp() as PadelScoreApp;
}

function buildRootNavigation(service as MatchService) as [Views] or [Views, InputDelegates] {
    var match = service.activeMatch;
    if (match == null) {
        return [new StartView(service), new StartDelegate(service)] as [Views] or [Views, InputDelegates];
    }
    if (match.status == MatchStatus.IN_PROGRESS) {
        if (match.needsServerSelection) {
            return [new SelectServerView(service), new SelectServerDelegate(service)] as [Views] or [Views, InputDelegates];
        }
        var pager = new MatchPagerView(service, 0);
        return [pager, new MatchPagerDelegate(service, pager)] as [Views] or [Views, InputDelegates];
    }
    if (match.status == MatchStatus.COMPLETED || match.status == MatchStatus.ENDED_EARLY) {
        return [new MatchCompleteView(service), new MatchCompleteDelegate(service)] as [Views] or [Views, InputDelegates];
    }
    return [new StartView(service), new StartDelegate(service)] as [Views] or [Views, InputDelegates];
}
