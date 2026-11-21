using StudyTimer.Domain.Entities;

namespace StudyTimer.Api;

public record BadgeDef(string Code, string Name, string Description, string Icon);

/// <summary>Règles de XP, niveaux, séries et badges.</summary>
public static class Gamification
{
    public const int DailyGoalSeconds = 600;   // 10 min validées pour un jour de série

    /// <summary>1 XP par minute étudiée, +10 XP de bonus pour une séance d'au moins 25 min.</summary>
    public static int XpFor(int seconds) =>
        seconds < 60 ? 0 : seconds / 60 + (seconds >= 1500 ? 10 : 0);

    /// <summary>Niveau n atteint à 100 × (n-1)² XP (niveau 1 = 0 XP, niveau 2 = 100, niveau 3 = 400...).</summary>
    public static (int level, int xpIntoLevel, int xpForNext) Level(int xp)
    {
        var level = (int)Math.Floor(Math.Sqrt(Math.Max(0, xp) / 100.0)) + 1;
        var floor = 100 * (level - 1) * (level - 1);
        var next = 100 * level * level;
        return (level, xp - floor, next - floor);
    }

    public static readonly BadgeDef[] Badges =
    {
        new("first_session", "Premier pas",     "Terminer sa première séance",          "flag"),
        new("sessions_25",   "Assidu",          "Terminer 25 séances",                  "repeat"),
        new("hours_10",      "10 heures",       "Cumuler 10 heures d'étude",            "schedule"),
        new("hours_50",      "50 heures",       "Cumuler 50 heures d'étude",            "workspace_premium"),
        new("streak_3",      "Série de 3",      "3 jours consécutifs d'étude",          "local_fire_department"),
        new("streak_7",      "Série de 7",      "7 jours consécutifs d'étude",          "whatshot"),
        new("streak_30",     "Série de 30",     "30 jours consécutifs d'étude",         "military_tech"),
        new("marathon_60",   "Marathon",        "Une séance d'au moins 60 minutes",     "directions_run"),
    };

    /// <summary>Plus longue série de jours consécutifs dont le total atteint l'objectif.</summary>
    public static int BestStreak(IEnumerable<(DateOnly day, int seconds)> items)
    {
        var days = items.GroupBy(i => i.day)
            .Where(g => g.Sum(x => x.seconds) >= DailyGoalSeconds)
            .Select(g => g.Key).OrderBy(d => d).ToList();
        int best = 0, run = 0; DateOnly? prev = null;
        foreach (var d in days)
        {
            run = prev is not null && d == prev.Value.AddDays(1) ? run + 1 : 1;
            best = Math.Max(best, run);
            prev = d;
        }
        return best;
    }

    public static HashSet<string> Earned(IReadOnlyCollection<(DateOnly day, int seconds)> sessions)
    {
        var set = new HashSet<string>();
        var total = sessions.Sum(s => s.seconds);
        var streak = BestStreak(sessions);
        if (sessions.Count >= 1) set.Add("first_session");
        if (sessions.Count >= 25) set.Add("sessions_25");
        if (total >= 10 * 3600) set.Add("hours_10");
        if (total >= 50 * 3600) set.Add("hours_50");
        if (streak >= 3) set.Add("streak_3");
        if (streak >= 7) set.Add("streak_7");
        if (streak >= 30) set.Add("streak_30");
        if (sessions.Any(s => s.seconds >= 3600)) set.Add("marathon_60");
        return set;
    }

    /// <summary>Progression d'un participant à un défi, à partir de ses séances terminées dans la fenêtre du défi.</summary>
    public static int Progress(Challenge c, IEnumerable<(DateTime startedUtc, int seconds)> sessions)
    {
        var inWindow = sessions.Where(s => s.startedUtc >= c.StartsAtUtc && s.startedUtc <= c.EndsAtUtc).ToList();
        return c.Type switch
        {
            ChallengeType.TotalTime => inWindow.Sum(s => s.seconds),
            ChallengeType.SessionCount => inWindow.Count,
            ChallengeType.LongestSession => inWindow.Count == 0 ? 0 : inWindow.Max(s => s.seconds),
            ChallengeType.DailyStreak => BestStreak(inWindow.Select(s => (DateOnly.FromDateTime(s.startedUtc), s.seconds))),
            _ => 0
        };
    }
}
