import SwiftUI

struct TrackerBrandIcon: View {
    let service: TrackingService
    var body: some View {
        Group {
            if service.key == "anilist" {
                Image("AniListLogo").resizable().scaledToFit()
            } else if service.comingSoon {
                Image("MyAnimeListLogo").resizable().scaledToFit()
            } else {
                CoverImage(url: BackendAPI.coverURL(service.iconUrl), symbol: "Broadcast")
            }
        }.clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
    }
}
