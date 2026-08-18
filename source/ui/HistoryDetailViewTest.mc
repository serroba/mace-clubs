import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

(:test)
module HistoryDetailFixtures {
    function detailedRecord() as Array<Storage.ValueType> {
        var blocks = [] as Array<WorkBlockSummary>;
        var first = new WorkBlockSummary(
            1,
            120,
            Movement.TYPE_360,
            Movement.SIDE_LEFT,
            Equipment.TYPE_MACE,
            1,
            4000,
            0,
            82
        );
        first.setRestSeconds(60);
        first.setSwings(48);
        blocks.add(first);
        blocks.add(
            new WorkBlockSummary(
                2,
                90,
                Movement.TYPE_360,
                Movement.SIDE_RIGHT,
                Equipment.TYPE_MACE,
                1,
                4000,
                0,
                -1
            )
        );
        var rec = SmoothnessLog.record(
            1700000000,
            Equipment.TYPE_MACE,
            1,
            4000,
            Movement.TYPE_360,
            Movement.SIDE_ALTERNATING,
            80,
            [82, -1] as Array<Number>
        );
        return SmoothnessLog.withDetails(rec, 210, 60, blocks);
    }
}

(:test)
function testHistoryDetailScrollWrapsThroughOverviewAndSets(logger as Test.Logger) as Boolean {
    var view = new HistoryDetailView(HistoryDetailFixtures.detailedRecord());
    RenderTestSupport.render(view);
    view.scroll(1);
    RenderTestSupport.render(view);
    view.scroll(1);
    RenderTestSupport.render(view);
    // Two sets plus the overview: a third scroll wraps back to the overview.
    view.scroll(1);
    RenderTestSupport.render(view);
    view.scroll(-1);
    RenderTestSupport.render(view);
    return true;
}

(:test)
function testHistoryDetailRendersLegacyRecordsWithoutDetails(logger as Test.Logger) as Boolean {
    var rec = SmoothnessLog.record(
        1700000000,
        Equipment.TYPE_CLUBS,
        2,
        4000,
        Movement.TYPE_MILL,
        Movement.SIDE_TWO_HANDED,
        75,
        [75] as Array<Number>
    );
    var view = new HistoryDetailView(rec);
    RenderTestSupport.render(view);
    view.scroll(1);
    RenderTestSupport.render(view);
    return true;
}
