import Testing
@testable import LetsMakeAlbums

struct ClusterFormattingTests {

    @Test func dateRangeSingleDay() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let result = ClusterFormatting.dateRange(startDate: date, endDate: date)
        #expect(!result.isEmpty)
    }
}
