"""Pure subscription matching, title parsing, and scoring helpers.

The preview endpoint and the background worker both use this module. Keeping
the decision logic independent from SQLAlchemy makes the matching rules easy
to test and prevents the UI preview from drifting away from the worker.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, date, datetime
import math
import re
from typing import Any, Iterable


DEFAULT_PROFILE_VALUES: dict[str, Any] = {
    "language_mode": "简",
    "language_unknown": "accept",
    "must_include": [],
    "exclude_tokens": [],
    "prefer_resolution": ["1080p", "2160p"],
    "prefer_codec": ["av1", "hevc", "avc"],
    # 简/繁 rank here too, so a locked group's 简 release outranks its 繁 one.
    "prefer_subtitle": ["简", "繁", "日", "无"],
    "prefer_bitdepth": ["10bit", "8bit"],
    "weights": {"fansub": 45, "resolution": 22, "codec": 15, "subtitle": 12, "bitdepth": 6},
    "neutral_score": 0.5,
    "accept_now_score": 0.85,
    "grace_hours": 3.0,
}


@dataclass(frozen=True)
class ProfileValues:
    language_mode: str = "简"
    language_unknown: str = "accept"
    must_include: tuple[str, ...] = ()
    exclude_tokens: tuple[str, ...] = ()
    prefer_resolution: tuple[str, ...] = ("1080p", "2160p")
    prefer_codec: tuple[str, ...] = ("av1", "hevc", "avc")
    prefer_subtitle: tuple[str, ...] = ("简", "繁", "日", "无")
    prefer_bitdepth: tuple[str, ...] = ("10bit", "8bit")
    weights: dict[str, float] = field(
        default_factory=lambda: {
            "fansub": 45,
            "resolution": 22,
            "codec": 15,
            "subtitle": 12,
            "bitdepth": 6,
        }
    )
    neutral_score: float = 0.5
    accept_now_score: float = 0.85
    grace_hours: float = 3.0


@dataclass(frozen=True)
class SubscriptionRules:
    bangumi_id: int
    anime_name: str = ""
    anime_name_cn: str = ""
    aliases: tuple[str, ...] = ()
    # One locked group, not a priority list: a season assembled from whoever
    # published first mixes naming, timing and styling across episodes.
    fansub: str = ""
    allow_no_fansub: bool = False
    search_keywords: tuple[str, ...] = ()
    must_include: tuple[str, ...] = ()
    exclude_keywords: tuple[str, ...] = ()
    use_subject_id: bool = True
    resource_types: tuple[str, ...] = ("动画",)
    episode_offset_override: int | None = None


@dataclass(frozen=True)
class EpisodeInfo:
    ep: float
    sort: float
    name: str = ""
    name_cn: str = ""
    airdate: datetime | date | str | None = None

    @property
    def index(self) -> int | None:
        if not math.isfinite(self.ep) or not self.ep.is_integer() or self.ep <= 0:
            return None
        return int(self.ep)


@dataclass(frozen=True)
class EpisodeParseResult:
    index: int | None
    raw_number: float | None = None
    episode: EpisodeInfo | None = None
    reason: str | None = None
    season_number: int | None = None
    # ``True`` means "ask again later", not "give up": the title parsed fine but
    # Bangumi has no episode table yet, which is the normal state of a show
    # subscribed before it airs. A deferred resource must never be turned into
    # ``needs_review`` -- nobody would ever clear that queue entry.
    deferred: bool = False


UNAIRED = "unaired"
AIRING = "airing"
FINISHED = "finished"
UNKNOWN = "unknown"


@dataclass(frozen=True)
class ResourceEvaluation:
    accepted: bool
    score: float
    reason: str | None
    attributes: dict[str, Any]
    component_scores: dict[str, float]


def _string_list(value: Any) -> tuple[str, ...]:
    if not isinstance(value, (list, tuple)):
        return ()
    return tuple(str(item).strip() for item in value if str(item).strip())


def _float_map(value: Any) -> dict[str, float]:
    if not isinstance(value, dict):
        return {}
    result: dict[str, float] = {}
    for key, item in value.items():
        try:
            result[str(key)] = float(item)
        except (TypeError, ValueError):
            continue
    return result


def profile_values(profile: Any | None, overrides: dict[str, Any] | None = None) -> ProfileValues:
    """Materialize a profile plus partial per-subscription overrides."""
    values = dict(DEFAULT_PROFILE_VALUES)
    if profile is not None:
        for key in values:
            if hasattr(profile, key):
                values[key] = getattr(profile, key)
    if overrides:
        for key, value in overrides.items():
            if key in values and value is not None:
                values[key] = value

    language_mode = str(values.get("language_mode") or "简")
    if language_mode not in {"any", "简", "繁"}:
        language_mode = "简"
    language_unknown = str(values.get("language_unknown") or "accept")
    if language_unknown not in {"accept", "reject"}:
        language_unknown = "accept"

    def bounded_float(key: str, default: float, low: float = 0.0) -> float:
        try:
            return max(low, float(values.get(key, default)))
        except (TypeError, ValueError):
            return default

    return ProfileValues(
        language_mode=language_mode,
        language_unknown=language_unknown,
        must_include=_string_list(values.get("must_include")),
        exclude_tokens=_string_list(values.get("exclude_tokens")),
        prefer_resolution=_string_list(values.get("prefer_resolution")),
        prefer_codec=_string_list(values.get("prefer_codec")),
        prefer_subtitle=_string_list(values.get("prefer_subtitle")),
        prefer_bitdepth=_string_list(values.get("prefer_bitdepth")),
        weights=_float_map(values.get("weights")) or dict(DEFAULT_PROFILE_VALUES["weights"]),
        neutral_score=min(1.0, bounded_float("neutral_score", 0.5)),
        accept_now_score=min(1.0, bounded_float("accept_now_score", 0.85)),
        grace_hours=bounded_float("grace_hours", 3.0),
    )


def subscription_rules(subscription: Any, anime: Any | None = None) -> SubscriptionRules:
    return SubscriptionRules(
        bangumi_id=int(getattr(anime, "bangumi_id", 0) or 0),
        anime_name=str(getattr(anime, "name", "") or ""),
        anime_name_cn=str(getattr(anime, "name_cn", "") or ""),
        aliases=_string_list(getattr(anime, "aliases", None)),
        fansub=str(getattr(subscription, "fansub", "") or "").strip(),
        allow_no_fansub=bool(getattr(subscription, "allow_no_fansub", False)),
        search_keywords=_string_list(getattr(subscription, "search_keywords", None)),
        must_include=_string_list(getattr(subscription, "must_include", None)),
        exclude_keywords=_string_list(getattr(subscription, "exclude_keywords", None)),
        use_subject_id=bool(getattr(subscription, "use_subject_id", True)),
        resource_types=_string_list(getattr(subscription, "resource_types", None)) or ("动画",),
        episode_offset_override=getattr(subscription, "episode_offset_override", None),
    )


def _word_boundary(pattern: str) -> str:
    # ``_`` is a word character, so ``\b`` misses common title forms such as
    # ``AV1_opus``. Explicit lookarounds cover underscores, dots, and x.
    return rf"(?<![a-z0-9])(?:{pattern})(?![a-z0-9])"


_LANGUAGE_PATTERNS: tuple[tuple[set[str], bool, str], ...] = (
    ({"简", "繁"}, True, r"简繁日|簡繁日|简日繁|chs?&cht&jp"),
    ({"简"}, True, r"简日|簡日|chs&jp|gb&jp|sc&jp"),
    ({"繁"}, True, r"繁日|cht&jp|big5&jp|tc&jp"),
    ({"简", "繁"}, False, r"简繁|簡繁|繁简|chs?&cht|sc&tc|gb&big5"),
    ({"简"}, False, r"简体|簡體|简中|" + _word_boundary(r"chs|gb|sc")),
    ({"繁"}, False, r"繁体|繁體|繁中|" + _word_boundary(r"cht|big5|tc")),
    (set(), False, r"粤语|粵語|粤日|粵日"),
)

_SIMP = set("从开战记说汉学见关门时过这来对会后义无电场头语边谁龙灵万与术医儿岁传华车东马鸟鱼历罗虽变态样张")
_TRAD = set("從開戰記說漢學見關門時過這來對會後義無電場頭語邊誰龍靈萬與術醫兒歲傳華車東馬鳥魚歷羅雖變態樣張")


def detect_language(title: str) -> tuple[set[str] | None, bool]:
    low = title.lower()
    for script, has_jp, pattern in _LANGUAGE_PATTERNS:
        if re.search(pattern, low, flags=re.IGNORECASE):
            return set(script), has_jp

    simp = sum(character in _SIMP for character in title)
    trad = sum(character in _TRAD for character in title)
    if simp and not trad:
        return {"简"}, False
    if trad and not simp:
        return {"繁"}, False
    if simp and trad:
        return {"简", "繁"}, False
    return None, False


def parse_title_attributes(title: str, fansub: str = "") -> dict[str, Any]:
    low = title.lower()
    script, has_jp = detect_language(title)

    def first_match(patterns: Iterable[tuple[str, str]]) -> str | None:
        for value, pattern in patterns:
            if re.search(pattern, low, flags=re.IGNORECASE):
                return value
        return None

    return {
        "language": {
            "script": [item for item in ("简", "繁") if script and item in script],
            "has_jp": has_jp,
            "detected": script is not None,
        },
        "resolution": first_match(
            (
                ("2160p", r"2160p|3840x2160|" + _word_boundary("4k")),
                ("1080p", r"1080p?|1920x1080|fhd"),
                ("720p", r"720p?|1280x720"),
                ("480p", r"480p|848x480"),
            )
        ),
        "codec": first_match(
            (
                ("av1", _word_boundary("av1")),
                ("hevc", r"hevc|" + _word_boundary(r"h\.?265|x265")),
                ("avc", _word_boundary(r"avc|h\.?264|x264")),
            )
        ),
        "bitdepth": first_match(
            (
                ("10bit", r"10-?bits?|yuv420p10|hi10p"),
                ("8bit", r"(?<!\d)8-?bits?"),
            )
        ),
        "fansub": fansub,
    }


def _contains_all(title: str, values: Iterable[str]) -> bool:
    low = title.casefold()
    return all(value.casefold() in low for value in values if value)


def _contains_any(title: str, values: Iterable[str]) -> str | None:
    low = title.casefold()
    for value in values:
        if value and value.casefold() in low:
            return value
    return None


def known_names(rules: SubscriptionRules) -> tuple[str, ...]:
    """Every title this show is released under, most recognisable first.

    Bangumi's official name is often the one nobody uses: fansubs title their
    releases with the Chinese name or one of the 别名, so all of them count as
    the same show.
    """
    return tuple(
        name
        for name in merge_unique(
            (rules.anime_name_cn, rules.anime_name, *rules.aliases)
        )
        if len(name.strip()) >= 2
    )


def search_variants(rules: SubscriptionRules, limit: int = 4) -> tuple[tuple[str, ...], ...]:
    """Name queries to run separately and then merge.

    Upstream ANDs the terms inside one ``search``, so two names for the same
    show cannot be asked for at once -- each name is its own query and the
    results get deduped by resource id. [limit] caps the fan-out: a subject with
    a dozen 别名 would otherwise turn one check into dozens of feed requests.
    """
    if rules.search_keywords:
        # An explicit keyword list is a constraint the user typed, not a name to
        # guess at, so it stays a single AND group.
        return (rules.search_keywords,)
    return tuple((name,) for name in known_names(rules)[: max(1, limit)])


MATCHED_BY_SUBJECT = "subject"
MATCHED_BY_TITLE = "title"
MATCHED_BY_NOTHING = "none"


@dataclass(frozen=True)
class SubscriptionMatch:
    """Whether a resource belongs to a subscription, and on what evidence.

    ``matched_by`` is what separates proof from a guess: the indexer's
    ``subjectId`` *is* the Bangumi id, so a tagged resource is certain, while a
    title carrying one of the show's names is only likely -- two shows can share
    a short alias. Selection has to prefer the certain one.
    """

    matched: bool
    reason: str | None = None
    matched_by: str = MATCHED_BY_NOTHING

    @property
    def by_subject(self) -> bool:
        return self.matched_by == MATCHED_BY_SUBJECT


def resource_matches_subscription(resource: Any, rules: SubscriptionRules) -> SubscriptionMatch:
    resource_type = str(getattr(resource, "type", "") or "")
    if rules.resource_types and resource_type not in rules.resource_types:
        return SubscriptionMatch(
            False, f"资源类型不在允许列表: {resource_type or '未知'}"
        )

    title = str(getattr(resource, "title", "") or "")
    subject_ids = getattr(resource, "subject_ids", None)
    matched_by = MATCHED_BY_TITLE
    if rules.use_subject_id and subject_ids:
        if rules.bangumi_id not in subject_ids:
            return SubscriptionMatch(False, "Bangumi subject 不匹配")
        matched_by = MATCHED_BY_SUBJECT
    elif rules.use_subject_id and rules.bangumi_id:
        names = [*known_names(rules), *rules.search_keywords]
        names = [name.casefold() for name in names if len(name.strip()) >= 2]
        if names and not any(name in title.casefold() for name in names):
            return SubscriptionMatch(False, "标题未匹配番剧")

    if rules.search_keywords and not _contains_all(title, rules.search_keywords):
        return SubscriptionMatch(False, "未满足搜索关键词")
    return SubscriptionMatch(True, None, matched_by)


# Numbers that are not episode numbers: resolutions, encoder settings, audio
# layouts. Blanking them out before any episode pattern runs is what makes an
# unrestricted numeric match safe -- a value blocklist cannot work, because
# ``8`` and ``10`` are also legitimate episode numbers.
_TECHNICAL_NOISE = re.compile(
    r"""
      \d{3,4}[x×]\d{3,4}                                    # 1920x1080
    | \d{3,4}[pi](?![a-z0-9])                               # 1080p / 480i
    | \d{1,2}\s?-?\s?bits?                                  # 10bit / 8-bit
    | yuv\d+p\d+
    | hi\d+p
    | (?<![a-z0-9])(?:x\s?26\d|h\.?\s?26\d)                 # x264 / h.265
    | (?<![a-z0-9])(?:av1|hevc|avc|vp9)(?![a-z0-9])
    | (?<![a-z0-9])(?:aac|flac|opus|ac3|eac3|dts|ddp?)
      (?:\s?x\d|\s?\d\.\d)?(?![a-z0-9])                     # AAC 2.0 / AACx2
    | \d\s?\.\s?\d\s?(?:ch|声道)                             # 5.1ch
    | (?<![a-z0-9])big5(?![a-z0-9])
    | (?<![a-z0-9])v\d(?![a-z0-9])                          # v2 重发标记
    | \d{4}\s?[-./年]\s?\d{1,2}(?:\s?[-./月]\s?\d{1,2})?      # 2026-08-20
    """,
    flags=re.IGNORECASE | re.VERBOSE,
)

# Real ranges are written without spaces around the separator (``01-12``) or
# carry an explicit unit (``01-12话``). The spaced form is reserved for the
# ``作品 S2 - 05`` separator, which is a single episode.
_EPISODE_RANGE = re.compile(
    r"(?<![a-z0-9])\d{1,3}\s?[-~～－]\s?\d{1,3}\s*(?:话|話|集|eps?)"
    r"|(?<![a-z0-9])\d{1,3}[-~～－]\d{1,3}(?![a-z0-9])",
    flags=re.IGNORECASE,
)

_NON_MAIN_EPISODE = re.compile(
    # ``SP01`` / ``OVA2`` number their own sequence, so the token keeps its
    # meaning with a trailing number -- but ``SPY`` must not match.
    r"ncop|nced|特別編|特别篇|菜单|(?<![a-z0-9])(?:pv|sp|ova|oad|cm)\d{0,2}(?![a-z0-9])",
    flags=re.IGNORECASE,
)


def _strip_technical_noise(title: str) -> str:
    """Blank out encoder/audio/resolution tokens before episode parsing."""
    return _TECHNICAL_NOISE.sub(lambda match: " " * len(match.group(0)), title)


def _is_collection_or_special(title: str) -> str | None:
    masked = _strip_technical_noise(title).casefold()
    if re.search(r"合集|全集|batch|complete|pack", masked, flags=re.IGNORECASE):
        return "合集或批量资源"
    if _EPISODE_RANGE.search(masked):
        return "集数区间资源"
    if _NON_MAIN_EPISODE.search(masked):
        return "非正片资源"
    return None


def evaluate_resource(
    resource: Any,
    profile: ProfileValues,
    rules: SubscriptionRules,
) -> ResourceEvaluation:
    title = str(getattr(resource, "title", "") or "")
    fansub = str(getattr(resource, "fansub_name", "") or "").strip()
    attributes = parse_title_attributes(title, fansub)
    attributes["resource_type"] = str(getattr(resource, "type", "") or "")

    collection_reason = _is_collection_or_special(title)
    if collection_reason:
        return ResourceEvaluation(False, 0, collection_reason, attributes, {})

    if rules.fansub:
        if fansub.casefold() != rules.fansub.casefold():
            if not (not fansub and rules.allow_no_fansub):
                return ResourceEvaluation(
                    False, 0, f"字幕组不是锁定的 {rules.fansub}", attributes, {}
                )
    elif not fansub and not rules.allow_no_fansub:
        return ResourceEvaluation(False, 0, "未允许无字幕组资源", attributes, {})

    language = attributes["language"]
    script = set(language["script"])
    if not language["detected"]:
        if profile.language_unknown == "reject":
            return ResourceEvaluation(False, 0, "无法判定字幕字形", attributes, {})
    elif not script:
        return ResourceEvaluation(False, 0, "字幕语言被明确排除", attributes, {})
    elif not script.intersection({"简", "繁"} if profile.language_mode == "any" else {profile.language_mode}):
        return ResourceEvaluation(False, 0, "字幕字形不符合偏好", attributes, {})

    required = (*profile.must_include, *rules.must_include)
    missing = next(
        (value for value in required if value.casefold() not in title.casefold()),
        None,
    )
    if missing:
        return ResourceEvaluation(False, 0, f"缺少必含项: {missing}", attributes, {})

    excluded = _contains_any(title, (*profile.exclude_tokens, *rules.exclude_keywords))
    if excluded:
        return ResourceEvaluation(False, 0, f"命中排除项: {excluded}", attributes, {})

    component_scores = {
        # No locked group means the dimension was never configured, and a
        # resource without a fansub cannot be ranked against one -- both are
        # "unresolved", so they take the neutral score rather than zero.
        "fansub": _preference_score(
            fansub or None,
            (rules.fansub,) if rules.fansub else (),
            profile.neutral_score,
        ),
        "resolution": _preference_score(
            attributes["resolution"], profile.prefer_resolution, profile.neutral_score
        ),
        "codec": _preference_score(
            attributes["codec"], profile.prefer_codec, profile.neutral_score
        ),
        "subtitle": _subtitle_score(
            attributes["language"], profile.prefer_subtitle, profile.neutral_score
        ),
        "bitdepth": _preference_score(
            attributes["bitdepth"], profile.prefer_bitdepth, profile.neutral_score
        ),
    }
    weights = {
        key: weight
        for key, weight in profile.weights.items()
        if key in component_scores and weight > 0
    }
    denominator = sum(weights.values())
    score = (
        sum(weights[key] * component_scores[key] for key in weights) / denominator
        if denominator
        else 0
    )
    attributes["scores"] = component_scores
    attributes["total_score"] = score
    return ResourceEvaluation(True, score, None, attributes, component_scores)


def subtitle_tokens(language: dict[str, Any]) -> tuple[str, ...]:
    """The subtitle-type labels a release carries.

    CHS/CHT count as subtitle types here, not only as the language filter: with
    one fansub locked, the script is often the only thing separating that
    group's two releases of the same episode, and ``language_mode`` can only
    accept or reject one -- it cannot say "简 preferred, 繁 acceptable".
    """
    script = [item for item in ("简", "繁") if item in language.get("script", ())]
    tokens = [*script]
    if len(script) == 2:
        tokens.append("简繁")
    tokens.append("日" if language.get("has_jp") else "无")
    return tuple(tokens)


def _subtitle_score(
    language: dict[str, Any],
    preferences: Iterable[str],
    neutral: float,
) -> float:
    """The best-ranked subtitle type the release carries.

    A 简日 release earns its 简 rank rather than its 日 rank, so ordering 简
    above 繁 is enough to prefer one script without rejecting the other.
    """
    values = tuple(preferences)
    tokens = subtitle_tokens(language)
    if not values or not tokens:
        return neutral
    return max(_preference_score(token, values, neutral) for token in tokens)


def _preference_score(
    value: str | None,
    preferences: Iterable[str],
    neutral: float,
) -> float:
    if value is None:
        return neutral
    values = tuple(preferences)
    if not values:
        return neutral
    folded = value.casefold()
    for index, preference in enumerate(values):
        if preference.casefold() == folded:
            return 1 - index / len(values)
    return 0


def _as_datetime(value: datetime | date | str | None) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        result = value
    elif isinstance(value, date):
        result = datetime.combine(value, datetime.min.time())
    else:
        text = str(value).strip()
        if not text:
            return None
        try:
            result = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            try:
                result = datetime.fromisoformat(text[:10])
            except ValueError:
                return None
    if result.tzinfo:
        result = result.astimezone(UTC).replace(tzinfo=None)
    return result


def derive_airing_status(
    air_date: datetime | date | str | None,
    episodes: Iterable[EpisodeInfo] = (),
    now: datetime | None = None,
) -> str:
    """Bangumi exposes no status field, so derive it from dates.

    ``air_date`` (the subject's first-broadcast date) decides *unaired*, not the
    episode list: a show that has not started usually has no episode rows at all.
    The episode airdates only separate *airing* from *finished*.
    """
    current = now or datetime.now(UTC).replace(tzinfo=None)
    start = _as_datetime(air_date)
    airdates = [
        value
        for value in (_as_datetime(episode.airdate) for episode in episodes)
        if value is not None
    ]

    if start is None:
        # Without a first-broadcast date there is nothing to compare against.
        # A last airdate alone can still prove the show finished.
        if airdates and max(airdates) <= current:
            return FINISHED
        return UNKNOWN
    if start > current:
        return UNAIRED
    if not airdates:
        # Started, but no usable episode dates. Old shows commonly lack them,
        # and calling that "airing" only leaves an extra entry point around,
        # while calling it "unaired" would disable a download that does work.
        return FINISHED
    return FINISHED if max(airdates) <= current else AIRING


def aired_episode_indices(
    episodes: Iterable[EpisodeInfo],
    now: datetime | None = None,
) -> tuple[int, ...]:
    """Episode indices already broadcast, earliest first.

    An episode without a date counts as aired only when the whole season lacks
    dates -- old subjects commonly carry none, whereas a season that dates every
    episode it has published means a missing date is a future episode.
    """
    current = now or datetime.now(UTC).replace(tzinfo=None)
    indexed = [episode for episode in episodes if episode.index is not None]
    dated = any(_as_datetime(episode.airdate) is not None for episode in indexed)
    aired: set[int] = set()
    for episode in indexed:
        airdate = _as_datetime(episode.airdate)
        if airdate is None:
            if not dated:
                aired.add(episode.index)  # type: ignore[arg-type]
        elif airdate <= current:
            aired.add(episode.index)  # type: ignore[arg-type]
    return tuple(sorted(aired))


def season_start(
    air_date: datetime | date | str | None,
    episodes: Iterable[EpisodeInfo] = (),
) -> datetime | None:
    """Earliest known broadcast time of the season.

    The subject's own first-broadcast date can be later than its first episode
    (specials, pre-air screenings), so the episode dates get a vote too.
    """
    values = [
        value
        for value in (
            _as_datetime(air_date),
            *(_as_datetime(episode.airdate) for episode in episodes),
        )
        if value is not None
    ]
    return min(values) if values else None


def next_expected_episode(
    episodes: Iterable[EpisodeInfo],
    existing_indices: Iterable[int],
) -> tuple[int | None, datetime | None]:
    """The earliest episode not held locally, with its broadcast date.

    "Earliest missing" rather than "first not yet broadcast": a gap in the
    middle is exactly what the user wants surfaced, and an episode whose date
    has passed but is still absent says the worker has not found it yet.
    """
    held = set(existing_indices)
    candidates = sorted(
        (
            episode
            for episode in episodes
            if episode.index is not None and episode.index not in held
        ),
        key=lambda episode: episode.index or 0,
    )
    if not candidates:
        return None, None
    return candidates[0].index, _as_datetime(candidates[0].airdate)


def _infer_season_number(anime_name: str) -> int | None:
    patterns = (
        r"\bS(?:eason)?\s*0*(\d+)\b",
        r"\b(\d+)(?:st|nd|rd|th)\s+season\b",
        r"第\s*0*(\d+)\s*季",
    )
    for pattern in patterns:
        match = re.search(pattern, anime_name, flags=re.IGNORECASE)
        if match:
            return int(match.group(1))
    return None


def _extract_episode_number(title: str, anime_name: str = "") -> tuple[float | None, int | None, str | None]:
    season_match = re.search(
        r"(?<![a-z0-9])s0*(\d{1,2})e(\d{1,3})(?![a-z0-9])",
        title,
        flags=re.IGNORECASE,
    )
    if season_match:
        season_number = int(season_match.group(1))
        expected_season = _infer_season_number(anime_name)
        if expected_season is not None and expected_season != season_number:
            return None, season_number, "资源季数与番剧不匹配"
        return float(season_match.group(2)), season_number, None

    collection_reason = _is_collection_or_special(title)
    if collection_reason:
        return None, None, collection_reason

    # Episode patterns run against the masked title so that ``1080p``,
    # ``10bit`` and ``AAC 2.0`` cannot be mistaken for episode numbers.
    masked = _strip_technical_noise(title)
    patterns = (
        r"(?:第|(?<![a-z0-9])ep?)\s*[-_. ]?\s*(\d{1,3}(?:\.\d+)?)(?!\d)",
        r"[\[(]\s*-?\s*(\d{1,3}(?:\.\d+)?)\s*[\])]",
        r"(?:&nbsp;\s*|^|[\s._])-\s*(\d{1,3}(?:\.\d+)?)(?!\d)",
        r"(?:^|[\s._-])(\d{1,3}(?:\.\d+)?)(?:\s*(?:end|fin|完))?(?=$|[\s\]._()-])",
    )
    for pattern in patterns:
        for match in re.finditer(pattern, masked, flags=re.IGNORECASE):
            value = float(match.group(1))
            if value <= 0:
                continue
            return value, None, None
    return None, None, "无法从标题解析集数"


def _episode_number(value: float) -> int | None:
    if not math.isfinite(value) or not value.is_integer() or value <= 0:
        return None
    return int(value)


def _episode_candidates(number: int, episodes: Iterable[EpisodeInfo]) -> list[EpisodeInfo]:
    return [
        episode
        for episode in episodes
        if episode.index is not None and (episode.ep == number or episode.sort == number)
    ]


def parse_episode_index(
    title: str,
    episodes: Iterable[EpisodeInfo],
    resource_created_at: datetime | date | str | None = None,
    *,
    episode_offset_override: int | None = None,
    anime_name: str = "",
) -> EpisodeParseResult:
    raw_number, season_number, extraction_reason = _extract_episode_number(title, anime_name)
    if extraction_reason:
        return EpisodeParseResult(None, raw_number, reason=extraction_reason, season_number=season_number)
    if raw_number is None:
        return EpisodeParseResult(None, reason="无法从标题解析集数", season_number=season_number)

    number = _episode_number(raw_number)
    if number is None:
        return EpisodeParseResult(
            None,
            raw_number,
            reason="小数集需要人工确认",
            season_number=season_number,
        )

    episode_list = [episode for episode in episodes if episode.index is not None]
    if not episode_list:
        return EpisodeParseResult(
            None,
            raw_number,
            reason="Bangumi 尚无集数表，等待上游补全",
            season_number=season_number,
            deferred=True,
        )
    if episode_offset_override is not None:
        override_candidate = next(
            (episode for episode in episode_list if episode.ep == number - episode_offset_override),
            None,
        )
        if override_candidate:
            chosen = override_candidate
        else:
            chosen = None
    else:
        chosen = None

    candidates = _episode_candidates(number, episode_list)
    if chosen is None and candidates:
        unique_candidates: list[EpisodeInfo] = []
        for candidate in candidates:
            if candidate not in unique_candidates:
                unique_candidates.append(candidate)
        if len(unique_candidates) == 1:
            chosen = unique_candidates[0]
        else:
            created = _as_datetime(resource_created_at)
            if created is None:
                chosen = next(
                    (candidate for candidate in unique_candidates if candidate.ep == number),
                    unique_candidates[0],
                )
            else:
                chosen = min(
                    unique_candidates,
                    key=lambda candidate: abs(
                        (_as_datetime(candidate.airdate) or created) - created
                    ),
                )

    if chosen is None:
        return EpisodeParseResult(
            None,
            raw_number,
            reason="集数不在 Bangumi 当前季的 ep/sort 范围",
            season_number=season_number,
        )

    created = _as_datetime(resource_created_at)
    airdate = _as_datetime(chosen.airdate)
    if created is not None and airdate is not None and airdate > created:
        return EpisodeParseResult(
            None,
            raw_number,
            episode=chosen,
            reason="对应集数尚未播出，拦截疑似误解析",
            season_number=season_number,
        )
    return EpisodeParseResult(
        chosen.index,
        raw_number,
        episode=chosen,
        season_number=season_number,
    )


def merge_unique(values: Iterable[str]) -> tuple[str, ...]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        folded = value.casefold()
        if value and folded not in seen:
            seen.add(folded)
            result.append(value)
    return tuple(result)
