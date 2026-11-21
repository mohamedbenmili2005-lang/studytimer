using StudyTimer.Api;
using StudyTimer.Domain.Entities;

namespace StudyTimer.Tests;

public class GamificationTests
{
    [Theory]
    [InlineData(0, 0)]
    [InlineData(59, 0)]       // moins d'une minute : pas d'XP
    [InlineData(600, 10)]     // 10 min = 10 XP
    [InlineData(1500, 35)]    // 25 min = 25 XP + 10 de bonus
    [InlineData(3600, 70)]
    public void Xp_selon_la_duree(int seconds, int expected) =>
        Assert.Equal(expected, Gamification.XpFor(seconds));

    [Theory]
    [InlineData(0, 1)]
    [InlineData(99, 1)]
    [InlineData(100, 2)]
    [InlineData(399, 2)]
    [InlineData(400, 3)]
    public void Niveau_selon_xp(int xp, int level) =>
        Assert.Equal(level, Gamification.Level(xp).level);

    [Fact]
    public void Serie_compte_les_jours_consecutifs_au_dessus_de_10_minutes()
    {
        var d = new DateOnly(2026, 11, 1);
        var items = new[]
        {
            (d, 700), (d.AddDays(1), 650), (d.AddDays(2), 900),
            (d.AddDays(4), 900),             // trou le jour 3
            (d.AddDays(5), 100)              // sous le seuil : ne compte pas
        };
        Assert.Equal(3, Gamification.BestStreak(items));
    }

    [Fact]
    public void Badges_attribues_selon_les_regles()
    {
        var d = new DateOnly(2026, 11, 1);
        var s = new List<(DateOnly, int)> { (d, 3700) };
        var earned = Gamification.Earned(s);
        Assert.Contains("first_session", earned);
        Assert.Contains("marathon_60", earned);
        Assert.DoesNotContain("hours_10", earned);
    }

    [Theory]
    [InlineData(ChallengeType.TotalTime, 5400)]
    [InlineData(ChallengeType.SessionCount, 2)]
    [InlineData(ChallengeType.LongestSession, 3600)]
    [InlineData(ChallengeType.DailyStreak, 1)]
    public void Progression_des_4_types_de_defi(ChallengeType type, int expected)
    {
        var start = new DateTime(2026, 11, 1, 0, 0, 0, DateTimeKind.Utc);
        var c = new Challenge { Type = type, StartsAtUtc = start, EndsAtUtc = start.AddDays(7) };
        var sessions = new[]
        {
            (start.AddHours(8), 1800),
            (start.AddHours(10), 3600),
            (start.AddDays(30), 9999)   // hors fenêtre : ignoré
        };
        Assert.Equal(expected, Gamification.Progress(c, sessions));
    }
}
