import Foundation

// MARK: - Blocked Domains

enum BlockedDomains {
    static let social: [String] = [
        "reddit.com", "www.reddit.com", "old.reddit.com",
        "twitter.com", "www.twitter.com", "x.com", "www.x.com",
        "facebook.com", "www.facebook.com", "m.facebook.com",
        "instagram.com", "www.instagram.com",
        "tiktok.com", "www.tiktok.com",
        "linkedin.com", "www.linkedin.com",
        "threads.net", "www.threads.net",
        "mastodon.social",
        "bsky.app",
        "discord.com", "www.discord.com",
        "tumblr.com", "www.tumblr.com",
        "snapchat.com", "www.snapchat.com",
        "pinterest.com", "www.pinterest.com",
    ]

    static let video: [String] = [
        "youtube.com", "www.youtube.com", "m.youtube.com",
        "youtu.be",
        "twitch.tv", "www.twitch.tv",
        "netflix.com", "www.netflix.com",
        "hulu.com", "www.hulu.com",
        "disneyplus.com", "www.disneyplus.com",
        "primevideo.com", "www.primevideo.com",
        "hbomax.com", "www.hbomax.com",
        "max.com", "www.max.com",
        "crunchyroll.com", "www.crunchyroll.com",
        "vimeo.com", "www.vimeo.com",
        "dailymotion.com", "www.dailymotion.com",
    ]

    static let porn: [String] = [
        "pornhub.com", "www.pornhub.com",
        "xvideos.com", "www.xvideos.com",
        "xhamster.com", "www.xhamster.com",
        "xnxx.com", "www.xnxx.com",
        "redtube.com", "www.redtube.com",
        "youporn.com", "www.youporn.com",
        "spankbang.com", "www.spankbang.com",
        "onlyfans.com", "www.onlyfans.com",
        "chaturbate.com", "www.chaturbate.com",
        "fapello.com", "www.fapello.com",
        // Hentai / comics
        "nhentai.net", "www.nhentai.net",
        "e-hentai.org", "www.e-hentai.org", "exhentai.org",
        "rule34.xxx", "www.rule34.xxx", "rule34.paheal.net",
        "gelbooru.com", "www.gelbooru.com",
        "8muses.com", "www.8muses.com",
        "hentaifox.com", "www.hentaifox.com",
        "imhentai.xxx", "www.imhentai.xxx",
        "hitomi.la", "www.hitomi.la",
        "luscious.net", "www.luscious.net",
        "imagefap.com", "www.imagefap.com",
        "tube8.com", "www.tube8.com",
        "thisvid.com", "www.thisvid.com",
        "slutload.com", "www.slutload.com",
        "tnaflix.com", "www.tnaflix.com",
    ]

    static let gore: [String] = [
        "liveleak.com", "www.liveleak.com",
        "theync.com", "www.theync.com",
        "bestgore.fun", "www.bestgore.fun",
        "kaotic.com", "www.kaotic.com",
        "crazyshit.com", "www.crazyshit.com",
        "goregrish.com", "www.goregrish.com",
        "xgore.net", "www.xgore.net",
        "leakedreality.com", "www.leakedreality.com",
        "goretoday.com", "www.goretoday.com",
        "seegore.com", "www.seegore.com",
        "watchpeopledie.tv", "www.watchpeopledie.tv",
        "deathaddict.co",
    ]

    static let imageboard: [String] = [
        "4chan.org", "www.4chan.org",
        "4channel.org", "www.4channel.org",
        "i.4cdn.org", "a.4cdn.org", "s.4cdn.org", "t.4cdn.org", "is.4chan.org",
    ]

    static let news: [String] = [
        "news.ycombinator.com",
        "cnn.com", "www.cnn.com",
        "foxnews.com", "www.foxnews.com",
        "bbc.com", "www.bbc.com", "bbc.co.uk", "www.bbc.co.uk",
        "nytimes.com", "www.nytimes.com",
        "theguardian.com", "www.theguardian.com",
        "washingtonpost.com", "www.washingtonpost.com",
        "reuters.com", "www.reuters.com",
        "apnews.com", "www.apnews.com",
        "nbcnews.com", "www.nbcnews.com",
        "cnbc.com", "www.cnbc.com",
        "bloomberg.com", "www.bloomberg.com",
        "techcrunch.com",
        "theverge.com", "www.theverge.com",
        "arstechnica.com",
        "slashdot.org",
    ]
}

// MARK: - Timer Durations

enum TimerDurations {
    static let deepWorkMinutes: Int = 90
    static let breakMinutes: Int = 15
    static let longBreakMinutes: Int = 30
    static let overrideMinimumSeconds: Int = 30
    static let overrideTimedAccessMinutes: Int = 15
}

// MARK: - Override Phrases

enum OverridePhrases {
    static let pool: [String] = [
        "Lord Jesus Christ, Son of God, have mercy on me, a sinner.",
        "I am choosing distraction over the work God has placed before me.",
        "This impulse will pass. I do not need to act on it.",
        "Be still, and know that I am God.",
        "The cell will teach you everything.",
        "What I am about to do will not satisfy me.",
        "I am not my urges. I am the one who watches them.",
        "Return to your cell, and your cell will teach you everything.",
        "This is acedia. Name it and it loses power.",
        "The present moment is the only moment I have.",
        "Grant me the serenity to accept what I cannot change.",
        "I have already decided. I chose deep work.",
        "Stillness is the beginning of wisdom.",
        "Watch and pray, that ye enter not into temptation.",
        "The struggle itself is the practice.",
    ]
}

// MARK: - URL Keyword Blocking

/// Keywords and path segments checked against the active browser tab URL every 15 seconds.
/// Triggers the interception overlay as a soft block for content that /etc/hosts can't catch
/// (e.g. NSFW subreddits on an otherwise-allowed domain).
enum BlockedURLKeywords {
    /// URL path segments that indicate NSFW content on otherwise-allowed domains.
    static let paths: [String] = [
        "/r/gonewild", "/r/nsfw", "/r/porn", "/r/sex", "/r/hentai",
        "/r/rule34", "/r/realgirls", "/r/cumsluts",
    ]

    /// Substrings that anywhere in the URL indicate blocked content.
    static let keywords: [String] = [
        "porn", "xxx", "nsfw", "hentai", "gore",
        "rule34", "gonewild", "nude", "naked",
    ]
}

// AppConstants is defined in Shared/SharedConstants.swift
